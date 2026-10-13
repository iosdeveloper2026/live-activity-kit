#!/usr/bin/env ruby
# Stage 2: add LiveActivityKit to an app's Xcode project. Safe to run again (skips what's done).
#
#   ruby add_kit.rb --project App.xcodeproj [--kit <Git URL | local kit folder>] [--app-group group.x]
#                   [--widget LiveActivityWidget | --widget-target <existing extension>] [--new-widget]
#                   [--version 1.0.0] [--resource App/GoogleService-Info.plist] [--dry-run]
#
# Widget: if the app already has a WidgetKit extension, the kit joins it (adds LiveActivityKitWidget()
# to its WidgetBundle, or wraps a single @main Widget in a new bundle). --new-widget forces a
# separate extension instead.
#
# Adds: the kit package (local path or Git URL), LiveActivityKit to the app target, a widget
# extension target with one file using LiveActivityKitWidget, the embed step, App Group + push
# entitlements, and the Info.plist keys. Touches no screens or other source files.
require "fileutils"
require "optparse"
require "xcodeproj"

Encoding.default_external = Encoding::UTF_8

opts = { widget: "LiveActivityWidget", dry: false, version: "1.0.0", resources: [], kit: "https://github.com/iosdeveloper2026/live-activity-kit" }
OptionParser.new do |o|
  o.on("--project PATH") { |v| opts[:project] = v }
  o.on("--kit PATH_OR_URL") { |v| opts[:kit] = v }
  o.on("--app-group ID") { |v| opts[:group] = v }
  o.on("--widget NAME", "name for a new widget extension") { |v| opts[:widget] = v }
  o.on("--widget-target NAME", "existing extension to add the Live Activity to") { |v| opts[:widget_target] = v }
  o.on("--new-widget", "always create a separate widget extension") { opts[:new_widget] = true }
  o.on("--version VERSION", "minimum version for a Git URL") { |v| opts[:version] = v }
  o.on("--resource FILE", "add a file (e.g. GoogleService-Info.plist) to the app's resources") { |v| opts[:resources] << v }
  o.on("--dry-run") { opts[:dry] = true }
end.parse!
abort "--project is required" unless opts[:project]

project_path = File.expand_path(opts[:project])
root = File.dirname(project_path)
project = Xcodeproj::Project.open(project_path)
app = project.native_targets.find { |t| t.product_type == "com.apple.product-type.application" } or abort "No app target"
cfg = ->(t, key) { t.build_configurations.map { |c| c.build_settings[key] }.compact.first }
bundle_id = cfg.(app, "PRODUCT_BUNDLE_IDENTIFIER") or abort "App has no PRODUCT_BUNDLE_IDENTIFIER"
group_id = opts[:group] || "group.#{bundle_id}"
widget_name = opts[:widget]
widget_bundle = "#{bundle_id}.#{widget_name}"
deployment = [cfg.(app, "IPHONEOS_DEPLOYMENT_TARGET") || "17.0", "17.0"].max_by { |v| Gem::Version.new(v) }
team = cfg.(app, "DEVELOPMENT_TEAM")
changes = []
step = ->(text) { changes << text; puts((opts[:dry] ? "[plan] " : "[done] ") + text) }

# ---- 0. Compatibility checks (before changing anything) --------------------------------------
KIT_FIREBASE = [Gem::Version.new("12.19.2"), Gem::Version.new("13.0.0")] # the kit's Firebase range
podfile = File.join(root, "Podfile")
if File.exist?(podfile) && File.read(podfile) =~ /pod\s+['"]Firebase/
  abort "STOP: this app gets Firebase from CocoaPods. The kit brings Firebase through Swift Package Manager, " \
        "and having both causes duplicate-symbol errors. Move the app's Firebase to SPM (12.19.2+) first, or ask the user."
end
project.root_object.package_references.each do |r|
  next unless r.respond_to?(:repositoryURL) && r.repositoryURL.to_s.include?("firebase-ios-sdk")
  req = r.requirement || {}
  low = Gem::Version.new(req["minimumVersion"] || req["version"] || "0")
  high = case req["kind"]
         when "exactVersion" then Gem::Version.new(req["version"]) .bump rescue low
         when "upToNextMinorVersion" then Gem::Version.new("#{low.segments[0]}.#{low.segments[1].to_i + 1}.0")
         when "versionRange" then Gem::Version.new(req["maximumVersion"])
         else Gem::Version.new("#{low.segments[0] + 1}.0.0")
         end
  if high <= KIT_FIREBASE[0] || low >= KIT_FIREBASE[1]
    abort "STOP: the app pins firebase-ios-sdk #{req.inspect}. The kit needs 12.19.2 up to (not including) 13.0.0. " \
          "Update the app's Firebase package to 12.19.2 or later first (ask the user)."
  end
  puts "[check] App already uses firebase-ios-sdk #{req["minimumVersion"] || req["version"]}: compatible with the kit."
end
compose = File.read(File.join(project_path, "project.pbxproj")).include?("embedAndSignAppleFrameworkForXcode")

# In projects with synchronized folders, Xcode copies every file in the folder into the bundle, so a
# new Info.plist there clashes with the generated one ("Multiple commands produce .../Info.plist").
# Put new Info.plist files next to the project instead.
synced_dirs = project.objects.select { |o| o.isa == "PBXFileSystemSynchronizedRootGroup" }.map { |g| g.path.to_s }
plist_path = lambda do |preferred, flat_name|
  synced_dirs.any? { |d| preferred.start_with?(d + "/") } ? flat_name : preferred
end

# ---- 1. Package reference -------------------------------------------------------------------
local = !opts[:kit].start_with?("http", "git@")
kit_ref = project.root_object.package_references.find do |r|
  local ? r.respond_to?(:relative_path) && File.expand_path(r.relative_path, root) == File.expand_path(opts[:kit])
        : r.respond_to?(:repositoryURL) && r.repositoryURL == opts[:kit]
end
unless kit_ref
  if local
    kit_ref = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
    kit_ref.relative_path = Pathname.new(File.expand_path(opts[:kit])).relative_path_from(Pathname.new(root)).to_s
  else
    kit_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
    kit_ref.repositoryURL = opts[:kit]
    kit_ref.requirement = { "kind" => "upToNextMajorVersion", "minimumVersion" => opts[:version] }
  end
  project.root_object.package_references << kit_ref
  step.("Add package #{opts[:kit]}")
end

add_product = lambda do |target, product|
  next if target.package_product_dependencies.any? { |d| d.product_name == product }
  dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dep.package = kit_ref
  dep.product_name = product
  target.package_product_dependencies << dep
  file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  file.product_ref = dep
  target.frameworks_build_phase.files << file
  step.("Link #{product} to #{target.name}")
end
add_product.(app, "LiveActivityKit")

# ---- 2. Widget extension target -------------------------------------------------------------
# Swift files belonging to a target: classic file references, or a synchronized folder.
target_swift_files = lambda do |t|
  files = t.source_build_phase.files_references.compact.map { |r| r.real_path.to_s }.select { |f| f.end_with?(".swift") }
  if t.respond_to?(:file_system_synchronized_groups)
    (t.file_system_synchronized_groups || []).each { |g| files += Dir.glob(File.join(root, g.path.to_s, "**/*.swift")) }
  end
  files += Dir.glob(File.join(root, t.name, "**/*.swift")) if files.empty?
  files.uniq.select { |f| File.exist?(f) }
end
main_widget_file = lambda do |t|
  target_swift_files.(t).find { |f| File.read(f, encoding: "UTF-8") =~ /@main\s*(\n\s*)?struct\s+\w+\s*:\s*(WidgetBundle|Widget)\b/ }
end

existing = nil
unless opts[:new_widget] || project.native_targets.any? { |t| t.name == widget_name }
  candidates = project.native_targets.select { |t| t.product_type == "com.apple.product-type.app-extension" && main_widget_file.(t) }
  existing = opts[:widget_target] ? candidates.find { |t| t.name == opts[:widget_target] } : (candidates.size == 1 ? candidates.first : nil)
  abort "Widget extension #{opts[:widget_target]} not found or has no @main widget" if opts[:widget_target] && !existing
  if existing.nil? && candidates.size > 1
    abort "Several widget extensions (#{candidates.map(&:name).join(", ")}). Rerun with --widget-target <name> or --new-widget."
  end
end

if existing
  widget = existing
  widget_name = existing.name
  file = main_widget_file.(existing)
  source = File.read(file, encoding: "UTF-8")
  if source.include?("LiveActivityKitWidget()")
    # already added
  elsif source =~ /@main\s*(\n\s*)?struct\s+(\w+)\s*:\s*WidgetBundle\b/
    body = source.match(/var\s+body\s*:\s*some\s+Widget\s*\{[^\n]*\n/) or abort "Couldn't find `var body: some Widget {` in #{file}"
    indent = source[body.end(0)..][/\A[ \t]*/]
    updated = source[0...body.end(0)] + "#{indent}LiveActivityKitWidget()\n" + source[body.end(0)..]
    updated = updated.sub(/^(import [^\n]+\n)(?!.*^import [^\n]+\n)/m) { "#{$1}import LiveActivityKitWidget\n" } unless updated =~ /^import LiveActivityKitWidget/
    File.write(file, updated) unless opts[:dry]
    step.("Add LiveActivityKitWidget() to the existing WidgetBundle in #{file.sub(root + "/", "")}")
  else
    # A single @main Widget: move @main to a new bundle that holds both widgets.
    name = source[/@main\s*(?:\n\s*)?struct\s+(\w+)\s*:\s*Widget\b/, 1]
    unless opts[:dry]
      File.write(file, source.sub(/@main\s*(\n\s*)?(struct\s+#{name}\s*:\s*Widget\b)/, '\2'))
      bundle_file = File.join(File.dirname(file), "LiveActivityBundle.swift")
      File.write(bundle_file, <<~SWIFT)
        import LiveActivityKitWidget
        import SwiftUI
        import WidgetKit

        /// Added by LiveActivityKit: the app's widget plus the remote Live Activity.
        @main
        struct LiveActivityBundle: WidgetBundle {
            var body: some Widget {
                #{name}()
                LiveActivityKitWidget()
            }
        }
      SWIFT
      unless target_swift_files.(existing).include?(bundle_file) && existing.source_build_phase.files_references.empty?
        group = project.main_group.recursive_children.find { |g| g.is_a?(Xcodeproj::Project::Object::PBXGroup) && g.real_path.to_s == File.dirname(file) }
        existing.add_file_references([group.new_reference(bundle_file)]) if group
      end
    end
    step.("Move @main from #{name} to a new LiveActivityBundle (#{name}() + LiveActivityKitWidget())")
  end
  widget_ent = (existing.build_configurations.map { |c| c.build_settings["CODE_SIGN_ENTITLEMENTS"] }.compact.first)
  widget_info = (existing.build_configurations.map { |c| c.build_settings["INFOPLIST_FILE"] }.compact.first)
  unless widget_ent
    widget_ent = "#{widget_name}/#{widget_name}.entitlements"
    existing.build_configurations.each { |c| c.build_settings["CODE_SIGN_ENTITLEMENTS"] = widget_ent }
  end
  unless widget_info
    widget_info = plist_path.("#{widget_name}/LiveActivity-Info.plist", "#{widget_name}-LiveActivity-Info.plist")
    existing.build_configurations.each { |c| c.build_settings["INFOPLIST_FILE"] = widget_info }
  end
end

widget ||= project.native_targets.find { |t| t.name == widget_name }
widget_dir = File.join(root, widget_name)
unless widget
  widget = project.new_target(:app_extension, widget_name, :ios, deployment, nil, :swift)
  widget.build_configurations.each do |c|
    s = c.build_settings
    s["PRODUCT_BUNDLE_IDENTIFIER"] = widget_bundle
    s["PRODUCT_NAME"] = "$(TARGET_NAME)"
    s["INFOPLIST_FILE"] = "#{widget_name}/Info.plist"
    s["GENERATE_INFOPLIST_FILE"] = "YES"
    s["CODE_SIGN_ENTITLEMENTS"] = "#{widget_name}/#{widget_name}.entitlements"
    s["CODE_SIGN_STYLE"] = "Automatic"
    s["DEVELOPMENT_TEAM"] = team if team
    s["SKIP_INSTALL"] = "YES"
    s["SWIFT_VERSION"] = cfg.(app, "SWIFT_VERSION") || "5.0"
    s["TARGETED_DEVICE_FAMILY"] = cfg.(app, "TARGETED_DEVICE_FAMILY") || "1,2"
    s["LD_RUNPATH_SEARCH_PATHS"] = "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks"
    s["MARKETING_VERSION"] = cfg.(app, "MARKETING_VERSION") || "1.0"
    s["CURRENT_PROJECT_VERSION"] = cfg.(app, "CURRENT_PROJECT_VERSION") || "1"
  end
  step.("Create widget extension target #{widget_name} (#{widget_bundle})")

  group = project.main_group.find_subpath(widget_name, true)
  group.set_source_tree("<group>")
  group.set_path(widget_name)
  unless opts[:dry]
    FileUtils.mkdir_p(widget_dir)
    File.write(File.join(widget_dir, "AppWidgets.swift"), File.read(File.join(__dir__, "..", "templates", "AppWidgets.swift")))
  end
  widget.add_file_references([group.new_reference("AppWidgets.swift")])
  step.("Add #{widget_name}/AppWidgets.swift (one file: LiveActivityKitWidget())")

  # Embed the extension in the app and build it first.
  embed = app.copy_files_build_phases.find { |p| p.dst_subfolder_spec == "13" } || app.new_copy_files_build_phase("Embed Foundation Extensions")
  embed.dst_subfolder_spec = "13"
  embed.add_file_reference(widget.product_reference, true).settings = { "ATTRIBUTES" => ["RemoveHeadersOnCopy"] }
  app.add_dependency(widget)
  step.("Embed #{widget_name}.appex in #{app.name}")
end
add_product.(widget, "LiveActivityKitWidget")

# ---- 3. Entitlements -------------------------------------------------------------------------
edit_plist = lambda do |path, description, &change|
  path = path.sub(%r{\A\$\((SRCROOT|PROJECT_DIR)\)/}, "")
  full = File.join(root, path)
  data = File.exist?(full) ? Xcodeproj::Plist.read_from_path(full) : {}
  before = Marshal.load(Marshal.dump(data))
  change.call(data)
  next if data == before && File.exist?(full)
  unless opts[:dry]
    FileUtils.mkdir_p(File.dirname(full))
    Xcodeproj::Plist.write_to_path(data, full)
  end
  step.("#{description}: #{path}")
end
add_group = ->(d) { d["com.apple.security.application-groups"] = ((d["com.apple.security.application-groups"] || []) + [group_id]).uniq }

app_ent = cfg.(app, "CODE_SIGN_ENTITLEMENTS")
unless app_ent
  app_ent = "#{app.name}/#{app.name}.entitlements"
  app.build_configurations.each { |c| c.build_settings["CODE_SIGN_ENTITLEMENTS"] = app_ent }
end
edit_plist.(app_ent, "App entitlements (App Group #{group_id}, push)") do |d|
  add_group.(d)
  d["aps-environment"] ||= "development"
end
edit_plist.(widget_ent || "#{widget_name}/#{widget_name}.entitlements", "Widget entitlements (App Group #{group_id})") { |d| add_group.(d) }

# ---- 4. Info.plist ---------------------------------------------------------------------------
app_info = cfg.(app, "INFOPLIST_FILE")
unless app_info
  # Generated Info.plist: add a small file with the extra keys; Xcode merges both.
  app_info = plist_path.("#{app.name}/LiveActivity-Info.plist", "#{app.name}-LiveActivity-Info.plist")
  app.build_configurations.each { |c| c.build_settings["INFOPLIST_FILE"] = app_info }
end
edit_plist.(app_info, "App Info.plist (NSSupportsLiveActivities, LiveActivityAppGroup, remote-notification)") do |d|
  d["NSSupportsLiveActivities"] = true
  d["CADisableMinimumFrameDurationOnPhone"] = true if compose # Compose crashes at launch without it
  d["LiveActivityAppGroup"] = group_id
  d["UIBackgroundModes"] = ((d["UIBackgroundModes"] || []) + ["remote-notification"]).uniq
end
edit_plist.(widget_info || "#{widget_name}/Info.plist", "Widget Info.plist") do |d|
  d["NSExtension"] ||= { "NSExtensionPointIdentifier" => "com.apple.widgetkit-extension" }
  d["LiveActivityAppGroup"] = group_id
end

# ---- 5. Extra resources (e.g. GoogleService-Info.plist) ----------------------------------------
# Projects with synchronized folders pick files up automatically; classic projects need a reference.
opts[:resources].each do |file|
  full = File.expand_path(file, root)
  rel = Pathname.new(full).relative_path_from(Pathname.new(root)).to_s
  next if app.resources_build_phase.files_references.any? { |r| r.real_path.to_s == full }
  synced = project.objects.any? { |o| o.isa == "PBXFileSystemSynchronizedRootGroup" && rel.start_with?(o.path.to_s + "/") }
  next if synced
  parent = project.main_group.find_subpath(File.dirname(rel), false) || project.main_group
  ref = parent.files.find { |f| f.real_path.to_s == full } || parent.new_reference(full)
  app.resources_build_phase.add_file_reference(ref, true)
  step.("Add #{rel} to #{app.name} resources")
end

# Deployment target: the kit needs iOS 17 (remote start itself needs 17.2 at runtime).
[app, widget].each do |t|
  t.build_configurations.each do |c|
    # A target without its own value inherits the project's setting for the same configuration.
    current = c.build_settings["IPHONEOS_DEPLOYMENT_TARGET"] ||
              project.build_configurations.find { |pc| pc.name == c.name }&.build_settings&.[]("IPHONEOS_DEPLOYMENT_TARGET")
    next if current && Gem::Version.new(current) >= Gem::Version.new("17.0")
    c.build_settings["IPHONEOS_DEPLOYMENT_TARGET"] = "17.0"
    step.("Raise #{t.name} (#{c.name}) deployment target to iOS 17.0")
  end
end

if changes.empty?
  puts "Nothing to do: LiveActivityKit is already set up in #{File.basename(project_path)}."
elsif opts[:dry]
  puts "\nDry run: #{changes.size} change(s) planned, nothing written."
else
  project.save
  puts "\nSaved #{File.basename(project_path)} (#{changes.size} change(s))."
end
