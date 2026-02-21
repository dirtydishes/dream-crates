from app.services.tagging import RulesTagger


def test_rules_tagger_detects_genre_and_tone_keywords():
    tagger = RulesTagger()
    genres, tones = tagger.classify(
        "Dark trap 808 sample pack",
        "Moody and gritty analog tape texture.",
    )

    assert genres
    assert tones
    assert genres[0].key == "trap"
    assert tones[0].key in {"dark", "gritty", "warm"}


def test_rules_tagger_taxonomy_is_non_empty():
    taxonomy = RulesTagger().taxonomy()

    assert "genres" in taxonomy
    assert "tones" in taxonomy
    assert len(taxonomy["genres"]) >= 8
    assert len(taxonomy["tones"]) >= 8
