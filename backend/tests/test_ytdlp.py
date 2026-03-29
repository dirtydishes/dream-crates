from app.services.ytdlp import pick_media_url


def test_pick_media_url_prefers_requested_audio_format():
    payload = {
        "requested_formats": [
            {"url": "https://video.example/video.mp4", "acodec": "none", "vcodec": "avc1"},
            {"url": "https://audio.example/audio.m4a", "acodec": "mp4a.40.2", "vcodec": "none"},
        ]
    }

    assert pick_media_url(payload) == "https://audio.example/audio.m4a"


def test_pick_media_url_prefers_best_audio_only_format():
    payload = {
        "formats": [
            {
                "url": "https://mixed.example/360.mp4",
                "acodec": "mp4a.40.2",
                "vcodec": "avc1",
                "tbr": 300,
            },
            {
                "url": "https://audio.example/low.m4a",
                "acodec": "mp4a.40.2",
                "vcodec": "none",
                "abr": 64,
            },
            {
                "url": "https://audio.example/high.m4a",
                "acodec": "mp4a.40.2",
                "vcodec": "none",
                "abr": 128,
            },
        ]
    }

    assert pick_media_url(payload) == "https://audio.example/high.m4a"


def test_pick_media_url_falls_back_to_direct_url():
    payload = {
        "url": "https://direct.example/audio.webm",
        "acodec": "opus",
        "vcodec": "none",
    }

    assert pick_media_url(payload) == "https://direct.example/audio.webm"
