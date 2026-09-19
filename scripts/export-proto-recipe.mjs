// Preserve the actual original web Proto proportions as inputs to the Blender pipeline.
import { createServer } from 'vite';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
const target = 'desktop/ArtSources/proto-archi-v1';
const server = await createServer({server:{middlewareMode:true},appType:'custom'});
try {
  const {visualProfileForStage} = await server.ssrLoadModule('/src/visual-growth.ts');
  const profile = visualProfileForStage('Hatchling');
  const sources = await Promise.all(['src/visual-growth.ts','src/proto-visual-rig.ts','src/main.ts'].map(async path =>
    ({path,sha256:createHash('sha256').update(await readFile(path)).digest('hex')})));
  const recipe = {schema:'archi-evolution-build/v2',id:'proto-archi-v1',lawVersion:1,
    purpose:'appearance-study',lineage:'original-proto-archi',family:'proto',
    reason:'Bring back OG Proto ARCHi alongside KIN, preserving the original round-sprout proportions and pearl core.',
    canonicalMutation:false,developmentEvidence:[],entropy:{direction:'unmeasured',effect:'unassessed'},
    sources, geometry:profile.geometry,core:profile.corePearl,
    surface:{color:[0.56,0.43,0.76,1],metallic:0.12,roughness:0.38},
    compactRadius:0.31,requiredPivots:['Arm.L','Arm.R','Crest'],
    export:{axisForward:'-Z',axisUp:'Y',bakeAnimation:false,framesPerSecond:30}};
  await mkdir(target,{recursive:true});
  // An explicit source refresh must not overwrite an authored revision.
  await writeFile(`${target}/recipe.json`,JSON.stringify(recipe,null,2)+'\n',{flag:'wx'});
  console.log('Recorded original Proto geometry and exact source digests.');
} finally { await server.close(); }
