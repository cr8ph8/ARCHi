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
    [Serializable] private sealed class Receipt {public string schema="archi-arena-rule-parity/v1";public string utc,sourceDigest,runID;public int bouts,rounds,assertions;public bool passed;}
    [Serializable] private sealed class LatestSuccess
    {
        public string schema="archi-arena-rule-parity-latest/v1";
        public string runID,receiptPath,receiptSHA256;
        public string scope="Mutable pointer to the last successful immutable receipt; not a new validation run.";
    }
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
        // Keep the old dated receipt untouched. New evidence is immutable; only
        // the explicitly named latest-success pointer is replaced.
        string output=Path.Combine(repository,"output/arena-rule-parity");
        receipt.runID=DateTime.UtcNow.ToString("yyyyMMddTHHmmssfffffffZ")+"-"+Guid.NewGuid().ToString("N");
        string runDirectory=Path.Combine(output,receipt.runID);
        Directory.CreateDirectory(runDirectory);
        string receiptPath=Path.Combine(runDirectory,"rule-parity.json");
        using(var file=new FileStream(receiptPath,FileMode.CreateNew,FileAccess.Write,FileShare.None))
        using(var writer=new StreamWriter(file))writer.Write(JsonUtility.ToJson(receipt,true));
        string receiptHash;
        using(var hash=SHA256.Create())receiptHash=BitConverter.ToString(hash.ComputeHash(File.ReadAllBytes(receiptPath))).Replace("-","").ToLowerInvariant();
        var latest=new LatestSuccess{runID=receipt.runID,receiptPath=receipt.runID+"/rule-parity.json",receiptSHA256=receiptHash};
        string pending=Path.Combine(output,"latest-success-"+receipt.runID+".tmp");
        using(var file=new FileStream(pending,FileMode.CreateNew,FileAccess.Write,FileShare.None))
        using(var writer=new StreamWriter(file))writer.Write(JsonUtility.ToJson(latest,true));
        string latestPath=Path.Combine(output,"latest-success.json");
        if(File.Exists(latestPath))File.Replace(pending,latestPath,null);
        else File.Move(pending,latestPath);
        Debug.Log("ARCHI_ARENA_PARITY_RECEIPT "+receiptPath);
        Debug.Log($"ARCHI_ARENA_PARITY_PASS {receipt.bouts} bouts / {receipt.rounds} rounds / {receipt.assertions} assertions");
    }
    private static void Check(bool success,string label,Receipt receipt){if(!success)throw new InvalidOperationException("Arena parity failed: "+label);receipt.assertions++;}
}
