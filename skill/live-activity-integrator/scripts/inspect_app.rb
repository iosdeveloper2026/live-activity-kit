#!/usr/bin/env ruby
# Stage 1: read an iOS app project and report what the integration needs. Changes nothing.
#
#   ruby inspect_app.rb <app folder or .xcodeproj>
#
# Prints a JSON report: project, app target, bundle ID, deployment target, UI stack, launch file,
# existing Firebase / widget / Live Activity setup, and suspicious build scripts.
require "json"
require "xcodeproj"

# Source files contain non-ASCII text (·, emoji); read everything as UTF-8.
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

path = ARGV[0] or abort "usage: inspect_app.rb <app folder or .xcodeproj>"
project_path =
  if path.end_with?(".xcodeproj") then path
  else
    found = Dir.glob(File.join(path, "**/*.xcodeproj")).reject { |p| p.include?("/Pods/") || p.include?("/build/") }
    abort "No .xcodeproj under #{path}" if found.empty?
    found.min_by(&:length)
  end
root = File.dirname(project_path)
project = Xcodeproj::Project.open(project_path)

def setting(target, key)
  target.build_configurations.map { |c| c.build_settings[key] }.compact.first
end

apps = project.native_targets.select { |t| t.product_type == "com.apple.product-type.application" }
abort "No iOS app target found" if apps.empty?
app = apps.first
extensions = project.native_targets.select { |t| t.product_type == "com.apple.product-type.app-extension" }

swift_files = Dir.glob(File.join(root, "**/*.swift")).reject { |p| p =~ %r{/(Pods|build|\.build|DerivedData)/} }
read = ->(f) { (File.read(f, encoding: "UTF-8") rescue "").scrub }

swiftui_entry = swift_files.find { |f| read.(f) =~ /^\s*@main\s*\n?\s*struct\s+\w+\s*:\s*App\b/m }
uikit_entry = swift_files.find { |f| read.(f) =~ /didFinishLaunchingWithOptions/ }
# Compose Multiplatform: the Xcode project runs the Kotlin framework build.
compose = read.(project_path + "/project.pbxproj").include?("embedAndSignAppleFrameworkForXcode")

packages = project.root_object.package_references.map { |r| r.respond_to?(:repositoryURL) ? r.repositoryURL : r.respond_to?(:relative_path) ? r.relative_path : r.to_s }
firebase_plist = Dir.glob(File.join(root, "**/GoogleService-Info.plist")).reject { |p| p.include?("/build/") }.first
bundle_id = setting(app, "PRODUCT_BUNDLE_IDENTIFIER")
firebase_bundle = firebase_plist ? `/usr/libexec/PlistBuddy -c "Print BUNDLE_ID" "#{firebase_plist}" 2>/dev/null`.strip : nil

# Supply-chain check: build phases that download and run code are a known malware pattern.
suspicious = project.native_targets.flat_map do |t|
  t.shell_script_build_phases.select { |p| p.shell_script.to_s =~ /(curl|wget)[^\n|]*\|\s*(ba|z)?sh|base64\s+(-d|--decode)|eval\s*\$\(/ }
                             .map { |p| { target: t.name, phase: p.name } }
end

target = setting(app, "IPHONEOS_DEPLOYMENT_TARGET") || project.build_configurations.map { |c| c.build_settings["IPHONEOS_DEPLOYMENT_TARGET"] }.compact.first
report = {
  project: project_path,
  objectVersion: project.object_version,
  appTarget: app.name,
  bundleId: bundle_id,
  team: setting(app, "DEVELOPMENT_TEAM"),
  deploymentTarget: target,
  remoteStartSupported: target.to_s.empty? ? nil : Gem::Version.new(target) >= Gem::Version.new("17.0"),
  uiStack: compose ? "compose-multiplatform" : swiftui_entry ? "swiftui" : uikit_entry ? "uikit" : "unknown",
  launchFile: swiftui_entry || uikit_entry,
  firebase: {
    plist: firebase_plist,
    plistBundleId: firebase_bundle,
    plistMatchesApp: firebase_bundle.nil? ? nil : firebase_bundle == bundle_id,
    sdkPackage: packages.any? { |p| p.to_s.include?("firebase-ios-sdk") },
    configuredInCode: swift_files.any? { |f| read.(f).include?("FirebaseApp.configure") },
  },
  existingWidgetExtensions: extensions.map(&:name),
  liveActivityKitInstalled: swift_files.any? { |f| read.(f).include?("LiveActivityKit.start") },
  existingLiveActivities: swift_files.select { |f| read.(f) =~ /:\s*ActivityAttributes\b/ }.map { |f| f.sub(root + "/", "") },
  suspiciousBuildPhases: suspicious,
  packages: packages,
}
puts JSON.pretty_generate(report)
