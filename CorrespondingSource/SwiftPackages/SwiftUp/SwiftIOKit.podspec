Pod::Spec.new do |s|
  s.name             = 'SwiftIOKit'
  s.version          = '0.1.2'
  s.summary          = 'Swift shallow wrapper of IOKit.'

  s.description      = <<-DESC
Swift shallow wrapper of IOKit.
Apple starts to provide Swift API for their libraries, but it is slow and
imperfect. These projects fill the gap.
                       DESC

  s.homepage         = 'https://github.com/youknowone/SwiftUp'
  s.license          = { :type => '2-clause BSD', :file => 'LICENSE' }
  s.author           = { 'Jeong YunWon' => 'jeong@youknowone.org' }
  s.source           = { :git => 'https://github.com/youknowone/SwiftUp.git', :tag => s.version.to_s }

  s.platform = :osx
  s.osx.deployment_target = "10.10"

  s.source_files = 'IOKit/SwiftIOKit/*.swift'

  s.frameworks = 'Foundation', 'IOKit'

  s.swift_versions = '5.0'
end
