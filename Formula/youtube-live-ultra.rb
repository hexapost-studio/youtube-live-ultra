# Documentation: https://docs.brew.sh/Formula-Cookbook
class YoutubeLiveUltra < Formula
  desc "Watch YouTube live streams with minimal latency and maximum resolution"
  homepage "https://github.com/hexapost-studio/youtube-live-ultra"
  url "https://github.com/hexapost-studio/youtube-live-ultra/archive/refs/tags/v#{version}.tar.gz"
  license "MIT"
  version "1.0.0"

  depends_on "streamlink"
  depends_on "mpv"
  depends_on "yt-dlp"

  def install
    # Install scripts
    bin.install "watch.sh" => "youtube-live-watch"
    bin.install "watch-ultra.sh" => "youtube-live-watch-ultra"
    bin.install "watch-ytdlp.sh" => "youtube-live-watch-ytdlp"
    bin.install "watch-resilient.sh" => "youtube-live-watch-resilient"

    # Install helper scripts
    bin.install Dir["scripts/*.sh"]

    # Install config
    (etc/"youtube-live-ultra").install "config/mpv.conf"
    (etc/"youtube-live-ultra").install "config/config.example"

    # Install documentation
    doc.install "README.md"
    doc.install "CHANGELOG.md"
  end

  def caveats
    <<~EOS
      Configuration:
        System-wide: #{etc}/youtube-live-ultra/
        Per-user:    ~/.config/youtube-live-ultra/

      Quick start:
        youtube-live-watch "https://www.youtube.com/watch?v=XXXXXXXXXXX"
        youtube-live-watch-resilient --mode ultra "https://www.youtube.com/watch?v=XXXXXXXXXXX"

      Health check before streaming:
        health-check.sh "https://www.youtube.com/watch?v=XXXXXXXXXXX"
    EOS
  end

  test do
    system "#{bin}/youtube-live-watch-resilient", "--help"
  end
end
