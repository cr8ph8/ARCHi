using System;
using System.IO;
using System.Security.Cryptography;
using UnityEditor;
using UnityEngine;
using ARCHi.Port;

public static class ArenaValidation
{
    [Serializable] private sealed class Corpus {public int schema;public string sourceDigest;public Case[] cases;}
    [Serializable] private sealed class Case {public string field;public int seed;public Step[] steps;}
    [Serializable] private sealed class Step {public string move,rival,winner;public int round,integrity,rivalIntegrity,spark,rivalSpark;public bool exposed,rivalExposed;}
    [Serializable] private sealed class Receipt {public string schema="archi-arena-rule-parity/v1";public string utc,sourceDigest;public int bouts,rounds,assertions;public bool passed;}
    [MenuItem("ARCHi/Arena/Validate Rule Parity")]
    public static void Validate()
    {
        string repository=Path.GetFullPath(Path.Combine(Application.dataPath,"../../.."));
        if(!Application.dataPath.EndsWith("/unity/ARCHi/Assets",StringComparison.Ordinal))throw new InvalidOperationException("Wrong Unity project.");
        var corpus=JsonUtility.FromJson<Corpus>(File.ReadAllText(Path.Combine(Application.dataPath,"ARCHi/Editor/Fixtures/arena-reference.json")));
        string digest;
        using(var hash=SHA256.Create())digest=BitConverter.ToString(hash.ComputeHash(File.ReadAllBytes(Path.Combine(repository,"src/battle-engine.ts")))).Replace("-","").ToLowerInvariant();
        if(corpus.schema!=1||corpus.sourceDigest!=digest)throw new InvalidOperationException("Regenerate parity fixtures after changing the retained engine.");
        var receipt=new Receipt{utc=DateTime.UtcNow.ToString("O"),sourceDigest=digest};
        foreach(var item in corpus.cases){
            var bout=new ArenaRehearsal(item.field=="guardian"?ArenaField.Guardian:ArenaField.Scout);
            foreach(var step in item.steps){
                Check(bout.RivalChoice().ToString().ToLowerInvariant()==step.rival,"rival policy",receipt);
                int before=bout.Round;
                Check(!bout.Resolve(ArenaMove.Pulse,before+1)&&bout.Round==before,"stale command rejected without mutation",receipt);
                Check(bout.Resolve((ArenaMove)Enum.Parse(typeof(ArenaMove),step.move,true),before),"move accepted",receipt);
                Check(bout.Round==step.round&&bout.Integrity==step.integrity&&bout.RivalIntegrity==step.rivalIntegrity,"round and simultaneous integrity",receipt);
                Check(bout.Spark==step.spark&&bout.RivalSpark==step.rivalSpark,"spark parity",receipt);
                Check(bout.Exposed==step.exposed&&bout.RivalExposed==step.rivalExposed,"exposure parity",receipt);
                Check(bout.Winner==step.winner,"outcome parity",receipt);receipt.rounds++;
            }
            Check(!bout.Resolve(ArenaMove.Pulse,bout.Round),"completed round rejected",receipt);
            var learning=new ArenaLearningPreview();
            Check(learning.Review(bout),"explicit completed experience review",receipt);
            Check(!learning.Review(bout)&&learning.ReviewedBouts==1,"repeated review does not duplicate evidence",receipt);
            Check(!learning.Review(new ArenaRehearsal(ArenaField.Guardian)),"unfinished practice cannot become evidence",receipt);
            receipt.bouts++;
        }
        var exhausted=new ArenaRehearsal(ArenaField.Guardian);
        for(int i=0;i<3;i++)Check(exhausted.Resolve(ArenaMove.Signature,exhausted.Round),"valid signature",receipt);
        int unchanged=exhausted.Round;
        Check(!exhausted.Resolve(ArenaMove.Signature,unchanged)&&exhausted.Round==unchanged,"empty spark cannot act",receipt);
        Check(!exhausted.Resolve((ArenaMove)99,unchanged),"unknown move rejected",receipt);
        receipt.passed=true;
        string output=Path.Combine(repository,"output/battle-evolution-2026-09-16");Directory.CreateDirectory(output);
        File.WriteAllText(Path.Combine(output,"rule-parity.json"),JsonUtility.ToJson(receipt,true));
        Debug.Log($"ARCHI_ARENA_PARITY_PASS {receipt.bouts} bouts / {receipt.rounds} rounds / {receipt.assertions} assertions");
    }
    private static void Check(bool success,string label,Receipt receipt){if(!success)throw new InvalidOperationException("Arena parity failed: "+label);receipt.assertions++;}
}
