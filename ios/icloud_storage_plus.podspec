#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint icloud_storage_plus.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'icloud_storage_plus'
  s.version          = '2.1.3'
  s.summary          = 'iCloud document storage for Flutter (iOS/macOS).'
  s.description      = <<-DESC
Flutter plugin for uploading, downloading, and managing files in an iCloud
container, with document coordination via UIDocument/NSDocument.
                       DESC
  s.homepage         = 'https://github.com/kingdomseed/icloud_storage_plus'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = 'kingdomseed'
  s.source           = { :path => '.' }
  s.source_files = [
    'icloud_storage_plus/Sources/icloud_storage_plus/**/*.{h,m,swift}',
    'icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedIO.swift',
    'icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift',
    'icloud_storage_plus/Sources/icloud_storage_plus_foundation/MetadataQuerySupport.swift',
    'icloud_storage_plus/Sources/icloud_storage_plus_foundation/MetadataQuerySession.swift',
    'icloud_storage_plus/Sources/icloud_storage_plus_foundation/WriteEntrypointPreflight.swift',
    'icloud_storage_plus/Sources/icloud_storage_plus_foundation/UbiquityContainerResolver.swift',
    'icloud_storage_plus/Sources/icloud_storage_plus_foundation/VersionExposure.swift',
    'icloud_storage_plus/Sources/icloud_storage_plus_foundation/PerPathMutationLane.swift',
    'icloud_storage_plus/Sources/icloud_storage_plus_foundation/UbiquitousItemMaterializer.swift',
  ]
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
