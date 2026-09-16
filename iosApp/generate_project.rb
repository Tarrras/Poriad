require 'xcodeproj'
root = File.dirname(__FILE__)
project = Xcodeproj::Project.new(File.join(root, 'Poruch.xcodeproj'))
target = project.new_target(:application, 'Poruch', :ios, '17.0')
group = project.main_group.new_group('Poruch', 'Poruch')
Dir.glob(File.join(root, 'Poruch', '*.swift')).sort.each { |f| target.source_build_phase.add_file_reference(group.new_file(File.basename(f))) }
group.new_file('Info.plist')
target.resources_build_phase.add_file_reference(group.new_file('Localizable.xcstrings'))
target.resources_build_phase.add_file_reference(group.new_file('PrivacyInfo.xcprivacy'))
project.root_object.development_region = 'uk'
project.root_object.known_regions = ['uk', 'Base']
config = project.main_group.new_file('Config.xcconfig')
package = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
package.repositoryURL = 'https://github.com/maplibre/maplibre-gl-native-distribution'
package.requirement = { 'kind' => 'exactVersion', 'version' => '6.28.0' }
project.root_object.package_references << package
product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
product.package = package; product.product_name = 'MapLibre'
target.package_product_dependencies << product
build = project.new(Xcodeproj::Project::Object::PBXBuildFile); build.product_ref = product; target.frameworks_build_phase.files << build
# KMP is a static framework. Build the appropriate framework before invoking Xcode.
target.build_configurations.each do |c|
 c.base_configuration_reference = config
 c.build_settings.merge!({
 'PRODUCT_BUNDLE_IDENTIFIER'=>'app.poruch.ios', 'SWIFT_VERSION'=>'5.0', 'INFOPLIST_FILE'=>'Poruch/Info.plist',
 'TARGETED_DEVICE_FAMILY'=>'1,2', 'ENABLE_USER_SCRIPT_SANDBOXING'=>'NO',
 # Тека фреймворку залежить від конфігурації: скрипт збирає link${CONFIGURATION}Framework,
 # тож Release має шукати releaseFramework, інакше архів лінкує застарілий debug.
 'FRAMEWORK_SEARCH_PATHS[sdk=iphonesimulator*]'=>"$(inherited) $(SRCROOT)/../shared/build/bin/iosSimulatorArm64/#{c.name.downcase}Framework",
 'FRAMEWORK_SEARCH_PATHS[sdk=iphoneos*]'=>"$(inherited) $(SRCROOT)/../shared/build/bin/iosArm64/#{c.name.downcase}Framework",
 'OTHER_LDFLAGS'=>'$(inherited) -framework Shared -lsqlite3', 'ARCHS'=>'arm64', 'CODE_SIGN_STYLE'=>'Automatic',
 'SWIFT_EMIT_LOC_STRINGS'=>'YES', 'IPHONEOS_DEPLOYMENT_TARGET'=>'17.0'
 })
end
project.save
scheme = Xcodeproj::XCScheme.new; scheme.add_build_target(target); scheme.set_launch_target(target); scheme.save_as(project.path, 'Poruch', true)
