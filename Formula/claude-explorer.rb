# Homebrew formula for claude-explorer
# To install from local tap:
#   brew tap kaymo-ai/claude-explorer https://github.com/kaymo-ai/claude-explorer
#   brew install claude-explorer

class ClaudeExplorer < Formula
  desc "Interactive viewer for Claude Code session data"
  homepage "https://github.com/kaymo-ai/claude-explorer"
  url "https://github.com/kaymo-ai/claude-explorer/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "d5558cd419c8d46bdc958064cb97f963d1ea793866414c025906ec15033512ed"
  license "MIT"
  head "https://github.com/kaymo-ai/claude-explorer.git", branch: "main"

  depends_on "python@3.11"

  def install
    bin.install "claude-explorer"
  end

  test do
    assert_match "Claude Explorer", shell_output("#{bin}/claude-explorer --version")
  end
end
