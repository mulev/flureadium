#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flureadium.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flureadium'
  s.version          = '0.19.5'
  s.summary          = 'Flutter plugin wrapper for Readium toolkits.'
  s.description      = <<-DESC
Reads EPUB ebooks, PDFs, audiobooks and comics through the Readium toolkits,
with text-to-speech, highlights and reading preferences.
                       DESC
  s.homepage         = 'http://github.com/mulev/flureadium'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Mikhail Mulev' => 'm.mulev@gmail.com' }
  s.source           = { :http => 'https://github.com/readium/podspecs' }
  s.source_files     = 'flureadium/Sources/flureadium/**/*.swift'
  s.resource_bundles = {'flureadium_privacy' => ['flureadium/Sources/flureadium/PrivacyInfo.xcprivacy']}
  s.dependency 'Flutter'
  s.dependency 'PromiseKit', '~> 8.1'
  s.dependency 'ReadiumShared', '~> 3.5.0'
  s.dependency 'ReadiumStreamer', '~> 3.5.0'
  s.dependency 'ReadiumNavigator', '~> 3.5.0'
  s.dependency 'ReadiumOPDS', '~> 3.5.0'
  s.dependency 'ReadiumAdapterGCDWebServer', '~> 3.5.0'
  # s.dependency 'ReadiumLCP', '~> 3.5.0'

  s.platform = :ios, '13.4'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'flureadium_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
