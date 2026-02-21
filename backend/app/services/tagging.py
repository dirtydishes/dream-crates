from collections import defaultdict

from app.models import TagScore


class RulesTagger:
    GENRE_RULES: dict[str, list[tuple[str, float]]] = {
        "trap": [("trap", 1.0), ("808", 0.8), ("hi-hat", 0.6)],
        "boom_bap": [("boom bap", 1.0), ("drum break", 0.8), ("90s", 0.5)],
        "drill": [("drill", 1.0), ("sliding 808", 0.9)],
        "lo_fi": [("lofi", 1.0), ("lo-fi", 1.0), ("dusty", 0.6), ("tape", 0.4)],
        "rnb": [("rnb", 1.0), ("r&b", 1.0), ("soulful", 0.6)],
        "ambient": [("ambient", 1.0), ("atmospheric", 0.8), ("drone", 0.7)],
        "house": [("house", 1.0), ("four on the floor", 0.8)],
        "techno": [("techno", 1.0), ("warehouse", 0.7)],
        "cinematic": [("cinematic", 1.0), ("score", 0.8), ("trailer", 0.7)],
        "phonk": [("phonk", 1.0), ("cowbell", 0.8)],
    }

    TONE_RULES: dict[str, list[tuple[str, float]]] = {
        "dark": [("dark", 1.0), ("moody", 0.8), ("ominous", 0.7)],
        "gritty": [("gritty", 1.0), ("dirty", 0.8), ("raw", 0.6)],
        "warm": [("warm", 1.0), ("analog", 0.8), ("tape", 0.6)],
        "melancholic": [("melancholic", 1.0), ("sad", 0.8), ("emotional", 0.6)],
        "dreamy": [("dreamy", 1.0), ("floating", 0.8), ("ethereal", 0.8)],
        "aggressive": [("aggressive", 1.0), ("hard", 0.7), ("heavy", 0.7)],
        "uplifting": [("uplifting", 1.0), ("bright", 0.8), ("hopeful", 0.6)],
        "eerie": [("eerie", 1.0), ("haunting", 0.8), ("creepy", 0.8)],
        "nostalgic": [("nostalgic", 1.0), ("retro", 0.7), ("vintage", 0.7)],
        "glossy": [("glossy", 1.0), ("polished", 0.7), ("clean", 0.5)],
    }

    def classify(self, title: str, description: str, top_n: int = 3) -> tuple[list[TagScore], list[TagScore]]:
        corpus = f"{title} {description}".lower()
        genres = self._score(self.GENRE_RULES, corpus, top_n=top_n)
        tones = self._score(self.TONE_RULES, corpus, top_n=top_n)
        return genres, tones

    def taxonomy(self) -> dict[str, list[str]]:
        return {
            "genres": sorted(self.GENRE_RULES.keys()),
            "tones": sorted(self.TONE_RULES.keys()),
        }

    def _score(self, rules: dict[str, list[tuple[str, float]]], corpus: str, top_n: int) -> list[TagScore]:
        raw_scores: dict[str, float] = defaultdict(float)

        for label, entries in rules.items():
            for keyword, weight in entries:
                if keyword in corpus:
                    raw_scores[label] += weight

        if not raw_scores:
            return []

        max_score = max(raw_scores.values())
        ranked = sorted(raw_scores.items(), key=lambda item: item[1], reverse=True)[:top_n]

        return [
            TagScore(key=label, confidence=round(score / max_score, 3))
            for label, score in ranked
        ]
