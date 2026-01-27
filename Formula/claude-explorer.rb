# Homebrew formula for claude-explorer
# To install from local tap:
#   brew tap kaymo-ai/claude-explorer https://github.com/kaymo-ai/claude-explorer
#   brew install claude-explorer

class ClaudeExplorer < Formula
  desc "Interactive viewer for Claude Code session data"
  homepage "https://github.com/kaymo-ai/claude-explorer"
  url "https://github.com/kaymo-ai/claude-explorer/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "5a5f318e975c43cb2704bec9ab17ce2d93fade76097e60439d2590d60f556eb7"
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
