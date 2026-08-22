#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint core_midi_input.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'core_midi_input'
  s.version          = '0.1.0'
  s.summary          = 'CoreMIDI input for the K.478 iOS TestFlight candidate.'
  s.description      = <<-DESC
Receives CoreMIDI source and channel events for the K.478 iOS USB MIDI
practice candidate. It does not request microphone, local-network or
Bluetooth permissions.
                       DESC
  s.homepage         = 'https://github.com/LIAB-BB/midi_music'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'LIAB' => 'noreply@example.invalid' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  s.resource_bundles = {
    'core_midi_input_privacy' => ['Resources/PrivacyInfo.xcprivacy']
  }
end
