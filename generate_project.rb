require 'xcodeproj'

project_name = 'skStats'
project = Xcodeproj::Project.new("#{project_name}.xcodeproj")

# Set deployment target higher to support SwiftUI MenuBarExtra
project.build_configurations.each do |config|
  config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '13.0'
  config.build_settings['SWIFT_VERSION'] = '5.0'
end

target = project.new_target(:application, project_name, :osx)

group = project.main_group.find_subpath(project_name, true)
group.set_source_tree('<group>')
group.set_path(project_name)

# Source files
['skStatsApp.swift', 'ContentView.swift', 'SystemMonitor.swift'].each do |file|
  file_ref = group.new_file(file)
  target.add_file_references([file_ref])
end

# Info.plist
group.new_file('Info.plist')

# Assets
assets_ref = group.new_file('Assets.xcassets')
target.resources_build_phase.add_file_reference(assets_ref)

target.build_configurations.each do |config|
  config.build_settings['INFOPLIST_FILE'] = "#{project_name}/Info.plist"
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = "com.ericsk.#{project_name}"
  config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = "AppIcon"
  config.build_settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = "AccentColor"
  config.build_settings['GENERATE_INFOPLIST_FILE'] = "NO"
  config.build_settings['DEVELOPMENT_TEAM'] = "" # Left blank for local building
end

project.save
puts "Successfully generated #{project_name}.xcodeproj!"
