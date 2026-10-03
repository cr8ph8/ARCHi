def recipe(title="Synthetic Staff", **changes):
    value = {
        "schema": "archi-item-design/v1", "title": title, "creator": "Synthetic Artist",
        "summary": "Disposable data-only recipe for service qualification.", "revision": 1,
        "license": "CC0", "palette": "mint", "crown": "leaf", "action": "decoration",
        "defaultGesture": {"pace": "Gentle", "sparkle": "Soft", "hold": "Brief"},
    }
    value.update(changes)
    return value


def provenance(**changes):
    value = {"declaration": "original", "attribution": "Synthetic test declaration only.",
             "source": "", "rightsConfirmed": True}
    value.update(changes)
    return value


def draft(title="Synthetic Staff", **changes):
    return {"recipe": recipe(title, **changes), "provenance": provenance()}


PASSWORD = "Disposable password only 2026"
