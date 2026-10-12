cask "peteshots" do
  version "1.1.0"
  sha256 "2fa0605b6438617c8eec7779c6209a4575d0b746dd0d7a80a18f6ecb28c22b78"

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
