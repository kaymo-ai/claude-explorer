# Homebrew formula for claude-explorer
# To install from local tap:
#   brew tap kaymo-ai/claude-explorer https://github.com/kaymo-ai/claude-explorer
#   brew install claude-explorer

class ClaudeExplorer < Formula
  desc "Interactive viewer for Claude Code session data"
  homepage "https://github.com/kaymo-ai/claude-explorer"
  url "https://github.com/kaymo-ai/claude-explorer/archive/refs/tags/v1.1.0.tar.gz"
  sha256 "94ddbc43e836c4962c2731e14d483a93c7d5ffab81dc5a469070b5695680b304"
  license "MIT"
  head "https://github.com/kaymo-ai/claude-explorer.git", branch: "main"

  depends_on "python@3.11"

  def install
    bin.install "claude_explorer.py" => "claude-explorer"
  end

  test do
    assert_match "Claude Explorer", shell_output("#{bin}/claude-explorer --version")
  end
end
