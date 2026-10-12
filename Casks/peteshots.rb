cask "peteshots" do
  version "1.0.0"
  sha256 "bf0b02201313e410adf7cf9a83ee62ca5192a3b16cdff25408bcea27bb7a17e7"

  url "https://github.com/petemcpherson/peteshots/releases/download/v#{version}/Peteshots-#{version}.dmg"
  name "Peteshots"
  desc "Menu bar screenshot tool with arrows, blur, text and crop"
  homepage "https://github.com/petemcpherson/peteshots"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :tahoe

  app "Peteshots.app"

  uninstall quit:       "com.peteshots.peteshots",
            login_item: "Peteshots"

  zap trash: [
    "~/Library/Application Scripts/com.peteshots.peteshots",
    "~/Library/Containers/com.peteshots.peteshots",
    "~/Library/Preferences/com.peteshots.peteshots.plist",
    "~/Library/Saved Application State/com.peteshots.peteshots.savedState",
  ]
end
