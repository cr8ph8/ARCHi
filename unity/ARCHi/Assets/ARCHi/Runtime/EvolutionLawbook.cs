using System;
using System.Collections.Generic;
using UnityEngine;

namespace ARCHi.Port
{
    [Serializable] public sealed class EvolutionLaw
    {
        public string id, title, text;
    }
    [Serializable] public sealed class EvolutionLawbook
    {
        public string schema, status;
        public int version;
        public EvolutionLaw[] laws;
        public static EvolutionLawbook Load()
        {
            var asset = Resources.Load<TextAsset>("Evolution/laws-v1");
            if (asset == null) throw new InvalidOperationException("Evolution laws are missing.");
            var book = JsonUtility.FromJson<EvolutionLawbook>(asset.text);
            var ids = new HashSet<string>();
            if (book == null || book.schema != "archi-evolution-laws/v1" || book.version != 1 || book.laws == null)
                throw new InvalidOperationException("Unsupported evolution laws.");
            foreach (var law in book.laws)
                if (law == null || string.IsNullOrWhiteSpace(law.title) || string.IsNullOrWhiteSpace(law.text) || !ids.Add(law.id))
                    throw new InvalidOperationException("Incomplete or duplicate evolution law.");
            if (!ids.SetEquals(new[] { "continuity", "cause", "evidence", "scope", "entropy", "care", "equipment", "counterplay", "correction", "authority", "craft", "plurality" }))
                throw new InvalidOperationException("Evolution law set is incomplete.");
            return book;
        }
    }
}
