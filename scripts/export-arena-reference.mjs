// Reproduce Unity's bounded rule parity corpus from the existing authoritative TS engine.
import { createServer } from 'vite';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
const server = await createServer({ server: { middlewareMode: true }, appType: 'custom' });
try {
  const e = await server.ssrLoadModule('/src/battle-engine.ts');
  const cases = [];
  for (const role of ['guardian', 'scout']) {
    for (let seed = 0; seed < 45; seed++) {
      const other = role === 'guardian' ? 'scout' : 'guardian';
      let state = e.createBattle('arena-reference', { id:'one',label:'KIN',bondRole:role,roster:[{id:'kin',name:'KIN',role}] },
        {id:'two',label:'Echo',bondRole:other,roster:[{id:'echo',name:'Echo',role:other}]});
      const steps=[];
      while(state.status === 'active') {
        const pattern = seed < 3 ? seed : ((seed * 17 + state.round * 13 + Math.floor(seed / state.round)) % 3);
        let move = ['pulse','guard','signature'][pattern];
        if(move === 'signature' && state.teams[0].spark === 0) move='pulse';
        const rival=e.choosePracticeCommand(state,'two');
        const result=e.resolveBattleRound(state,e.createBattleCommand(state,'one',move),rival);
        if(!result.accepted) throw Error(result.reason);
        state=result.state;
        steps.push({move, rival:rival.action, round:state.round, integrity:state.teams[0].roster[0].integrity,
          rivalIntegrity:state.teams[1].roster[0].integrity,spark:state.teams[0].spark,rivalSpark:state.teams[1].spark,
          exposed:state.teams[0].roster[0].exposed,rivalExposed:state.teams[1].roster[0].exposed,winner:state.winner??''});
      }
      cases.push({field:role,seed,steps});
    }
  }
  const sourceDigest=createHash('sha256').update(await readFile('src/battle-engine.ts')).digest('hex');
  const directory='unity/ARCHi/Assets/ARCHi/Editor/Fixtures';
  await mkdir(directory,{recursive:true});
  await writeFile(directory+'/arena-reference.json',JSON.stringify({schema:1,source:'src/battle-engine.ts',sourceDigest,cases},null,2)+'\n');
  console.log(JSON.stringify({cases:cases.length,rounds:cases.reduce((n,c)=>n+c.steps.length,0),sourceDigest}));
} finally { await server.close(); }
