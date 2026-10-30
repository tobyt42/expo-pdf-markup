#!/usr/bin/env ruby
# Adds an XCTest target to the example Xcode project for testing the ExpoPdfMarkup module.

require 'xcodeproj'

project_path = File.join(__dir__, '../example/ios/expopdfmarkupexample.xcodeproj')
proj = Xcodeproj::Project.open(project_path)

target_name = 'expopdfmarkupexampleTests'

app_target = proj.targets.find { |t| t.name == 'expopdfmarkupexample' }

abort 'Generated example app target was not found. Run Expo prebuild first.' unless app_target

# Create test target
test_target = proj.targets.find { |t| t.name == target_name } || proj.new_target(
  :unit_test_bundle,
  target_name,
  :ios,
  app_target.deployment_target
)
test_target.add_dependency(app_target)
test_target.build_configuration_list.build_configurations.each do |config|
  config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
  config.build_settings['TEST_HOST'] = "$(BUILT_PRODUCTS_DIR)/expopdfmarkupexample.app/expopdfmarkupexample"
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['INFOPLIST_FILE'] = ''
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['CODE_SIGN_IDENTITY'] = '-'
  config.build_settings['PRODUCT_NAME'] = target_name
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'dev.terhoeven.expopdfmarkup.example.tests'
end

# Create group and add files – source lives in ios/Tests/ relative to the repo root
tests_dir = File.join(__dir__, '../ios/Tests')
group = proj.main_group.groups.find { |g| g.name == target_name } ||
        proj.main_group.new_group(target_name, '../../ios/Tests')

Dir.glob(File.join(tests_dir, '*.swift')).each do |swift_file|
  file_ref = group.files.find { |f| f.path == File.basename(swift_file) } || group.new_file(File.basename(swift_file))
  test_target.source_build_phase.add_file_reference(file_ref, true)
end

Dir.glob(File.join(tests_dir, '*.pdf')).each do |resource_file|
  file_ref = group.files.find { |f| f.path == File.basename(resource_file) } || group.new_file(File.basename(resource_file))
  test_target.resources_build_phase.add_file_reference(file_ref, true)
end

# Add test target to the main scheme or create a scheme
scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(app_target, test_target)
scheme.save_as(proj.path, target_name, true)

proj.save

# Nest tests in the app's CocoaPods target so Expo/React Native module search
# paths are available to @testable imports after every clean prebuild.
podfile_path = File.join(__dir__, '../example/ios/Podfile')
podfile = File.read(podfile_path)
unless podfile.include?("target '#{target_name}' do")
  app_declaration = "target '#{app_target.name}' do\n"
  abort 'Generated Podfile app target was not found.' unless podfile.include?(app_declaration)
  podfile.sub!(app_declaration, "#{app_declaration}  target '#{target_name}' do\n    inherit! :search_paths\n  end\n\n")
  File.write(podfile_path, podfile)
end
puts "Test target '#{target_name}' added successfully."
