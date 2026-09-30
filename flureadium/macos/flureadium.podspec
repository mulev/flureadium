#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flureadium.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flureadium'
  s.version          = '0.19.6'
  s.summary          = 'Flutter plugin wrapper for Readium toolkits.'
  s.description      = <<-DESC
Reads EPUB ebooks, PDFs, audiobooks and comics through the Readium toolkits,
with text-to-speech, highlights and reading preferences.
                       DESC
  s.homepage         = 'http://github.com/mulev/flureadium'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Mikhail Mulev' => 'm.mulev@gmail.com' }

  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'

  # If your plugin requires a privacy manifest, for example if it collects user
  # data, update the PrivacyInfo.xcprivacy file to describe your plugin's
  # privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'flureadium_privacy' => ['Resources/PrivacyInfo.xcprivacy']}

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.15'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
