using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UIElements;

namespace ARCHi.Port
{
    /// <summary>Battle/evolution entry in the existing port. All new state is a disposable rehearsal.</summary>
    public sealed class ArenaWorkspace : MonoBehaviour
    {
        private static readonly Color Ink=new Color(.94f,.94f,.88f),Muted=new Color(.56f,.66f,.68f),Gold=new Color(.91f,.71f,.39f),Mint=new Color(.4f,.85f,.81f);
        private VisualElement overlay,host,leftPanel,rightPanel;
        private readonly List<VisualElement> hidden=new List<VisualElement>();
        private readonly List<StyleEnum<DisplayStyle>> displayStates=new List<StyleEnum<DisplayStyle>>();
        private Label kinValue,rivalValue,round,feedback,lesson,fieldLabel,motion,readiness,beingName;
        private VisualElement kinBar,rivalBar;
        private Button pulse,guard,signature,review,newBout,field,form,motionButton,staffButton,mantleButton,characterButton;
        private VisualElement seedReference,lawDetails;
        public bool ProtoSelected => Stage!=null&&Stage.ProtoSelected;
        public bool LawsOpen {get;private set;}
        private string CharacterName => nativeIdentity ? nativeName : ProtoSelected?"Proto ARCHi":"KIN";
        public ArenaStage3D Stage {get;private set;}
        public ArenaRehearsal Bout {get;private set;}
        public ArenaLearningPreview Learning {get;private set;}=new ArenaLearningPreview();
        public bool ReducedMotion {get;private set;}
        private bool body=true,resting;
        private bool wasBusy;
        private Action onClose;
        private int activityRounds;
        private bool nativeBound,nativeIdentity,nativeInputAllowed,nativeMotionPolicy,locallyStill,viewReleased;
        private string nativeName;
        private Button modeButton, rivalPulse, rivalGuard, rivalSignature;
        private Label rivalName, multiplayerStatus;
        private VisualElement rivalActions;
        public ArenaMultiplayerSession Multiplayer { get; private set; }
        public bool TwoPlayers => Multiplayer != null;
        public bool NativeIdentity => nativeIdentity;
        public bool NativeInputAllowed => !nativeBound || nativeInputAllowed;

        public void Initialize(VisualElement root,bool reduced,Action close)
        {
            host=root;onClose=close;ReducedMotion=reduced;
            foreach(var child in root.Children()){hidden.Add(child);displayStates.Add(child.style.display);child.style.display=DisplayStyle.None;}
            var art=new GameObject("Owned arena presentation");art.transform.SetParent(transform,false);Stage=art.AddComponent<ArenaStage3D>();Stage.Initialize();Stage.StaticMotion=reduced;
            Bout=new ArenaRehearsal(ArenaField.Guardian);
            overlay=new VisualElement{name="arena-workspace"};Absolute(overlay,0,0,0,0);overlay.style.backgroundColor=new Color(.015f,.025f,.038f);overlay.style.color=Ink;overlay.focusable=true;
            overlay.RegisterCallback<KeyDownEvent>(Key);overlay.RegisterCallback<GeometryChangedEvent>(Layout);
            root.Add(overlay);
            var image=new Image{name="arena-live-render",image=Stage.Texture,scaleMode=ScaleMode.ScaleAndCrop,pickingMode=PickingMode.Ignore};Absolute(image,0,0,65,138);overlay.Add(image);
            var header=new VisualElement{name="arena-header"};Absolute(header,0,0,0,float.NaN);header.style.height=140;
            header.style.paddingLeft=30;header.style.paddingTop=23;header.style.backgroundColor=new Color(.015f,.025f,.038f,.98f);
            header.Add(Text("ARCHi     /     BATTLE + BECOMING",11,Gold,true));
            var title=Text("The Resonance Garden",32,Ink,true);title.style.marginTop=9;header.Add(title);
            header.Add(Text("Experience leaves a trace. Wisdom gives it meaning.",12,Muted));overlay.Add(header);
            var navigation=Row();Absolute(navigation,float.NaN,30,28,float.NaN);
            navigation.Add(Button("Laws of becoming",ToggleLaws,"arena-laws"));
            navigation.Add(Button("Return to companion · B",Close,"arena-close"));overlay.Add(navigation);
            var badge=Row();Absolute(badge,float.NaN,32,84,float.NaN);badge.Add(Text("●   LOCAL REHEARSAL",10,Mint,true));overlay.Add(badge);

            leftPanel=Panel("arena-combat-readout");Absolute(leftPanel,30,float.NaN,150,float.NaN);leftPanel.style.width=200;
            leftPanel.style.bottom=240;
            var leftScroll=new ScrollView(ScrollViewMode.Vertical);leftScroll.style.flexGrow=1;leftScroll.style.minHeight=0;leftScroll.horizontalScrollerVisibility=ScrollerVisibility.Hidden;
            StyleScroll(leftScroll);
            var leftContent=new VisualElement();leftScroll.Add(leftContent);leftPanel.Add(leftScroll);
            leftContent.Add(Text("01  /  THE ENCOUNTER",10,Gold,true));
            round=Text("ROUND 01",20,Ink,true);round.style.marginTop=14;leftContent.Add(round);
            fieldLabel=Text("KIN · Guardian field",12,Gold,true);fieldLabel.style.marginTop=18;leftContent.Add(fieldLabel);
            kinValue=Text("36 / 36",24,Ink,true);leftContent.Add(kinValue);kinBar=Bar(leftContent,Gold);
            rivalName=Text("ECHO · practice partner",11,Mint,true);rivalName.style.marginTop=22;leftContent.Add(rivalName);
            rivalValue=Text("36 / 36",24,Ink,true);leftContent.Add(rivalValue);rivalBar=Bar(leftContent,Mint);
            readiness=Text("Ready · a fresh session",11,Muted);readiness.style.marginTop=18;leftContent.Add(readiness);
            field=Button("Train Scout field",ToggleField,"arena-field");field.style.marginTop=16;leftContent.Add(field);
            var rest=Button("Rest together",Rest,"arena-rest");leftContent.Add(rest);
            overlay.Add(leftPanel);

            rightPanel=Panel("arena-evolution-panel");Absolute(rightPanel,float.NaN,30,150,float.NaN);rightPanel.style.width=220;
            rightPanel.style.bottom=240;
            var rightScroll=new ScrollView(ScrollViewMode.Vertical);rightScroll.style.flexGrow=1;rightScroll.style.minHeight=0;
            rightScroll.horizontalScrollerVisibility=ScrollerVisibility.Hidden;
            StyleScroll(rightScroll);
            var rightContent=new VisualElement();rightScroll.Add(rightContent);rightPanel.Add(rightScroll);
            rightContent.Add(Text("02  /  BECOMING",10,Gold,true));
            beingName=Text("KIN",18,Ink,true);rightContent.Add(beingName);
            form=Button("Gather into Core Seed",ToggleForm,"arena-unfold");rightContent.Add(form);
            characterButton=Button("Study OG Proto ARCHi",ToggleCharacter,"arena-character");rightContent.Add(characterButton);
            var identityNote=Text("A character study starts fresh practice.",10,Muted);identityNote.name="arena-identity-note";rightContent.Add(identityNote);
            lesson=Text("Practice produces experience. Review its meaning before keeping a lesson.",11,Muted);lesson.style.marginTop=9;rightContent.Add(lesson);
            review=Button("Review this experience",()=>Review(),"arena-review");review.style.marginTop=14;rightContent.Add(review);
            var seed=Row();seedReference=seed;seed.style.marginTop=10;seed.style.alignItems=Align.Center;
            var seedImage=new Image{image=Resources.Load<Texture2D>("KIN/kin-core-seed-blender-v2"),scaleMode=ScaleMode.ScaleToFit};seedImage.style.width=32;seedImage.style.height=32;seed.Add(seedImage);
            seed.Add(Text("Same core. Same identity.\nSeed reference remains.",10,Gold));rightContent.Add(seed);
            var clothing=Text("ITEMS + EXPRESSION",10,Gold,true);clothing.style.marginTop=15;rightContent.Add(clothing);
            staffButton=Button("Equip Focus Staff",ToggleStaff,"arena-staff");rightContent.Add(staffButton);
            mantleButton=Button("Wear Starlight collar",ToggleMantle,"arena-mantle");rightContent.Add(mantleButton);
            rightContent.Add(Text("Wardrobe changes expression.\nCurrent battle power stays in the rules.",10,Muted));
            overlay.Add(rightPanel);

            var bottom=Panel("arena-action-panel");Absolute(bottom,30,30,float.NaN,22);bottom.style.paddingTop=12;bottom.style.paddingBottom=12;
            bottom.RegisterCallback<GeometryChangedEvent>(e=>FitPanelsAboveActions());
            var topLine=Row();topLine.style.alignItems=Align.Center;
            motion=Text("KIN / OBSERVE",11,Gold,true);topLine.Add(motion);var fill=new VisualElement();fill.style.flexGrow=1;topLine.Add(fill);
            modeButton=Button("2 players · M",ToggleTwoPlayers,"arena-two-players");topLine.Add(modeButton);
            motionButton=Button(reduced?"Motion: still":"Motion: full",ToggleMotion,"arena-motion");topLine.Add(motionButton);
            topLine.Add(Button("Stop",Stop,"arena-stop"));bottom.Add(topLine);
            var moves=Row();moves.style.marginTop=8;
            pulse=Button("1   PULSE  /  project",()=>Play(ArenaMove.Pulse),"arena-pulse",true);
            guard=Button("2   GUARD  /  protect",()=>Play(ArenaMove.Guard),"arena-guard",true);
            signature=Button("3   SIGNATURE  /  focus",()=>Play(ArenaMove.Signature),"arena-signature",true);
            foreach(var button in new[]{pulse,guard,signature}){button.style.flexGrow=1;button.style.height=44;moves.Add(button);}
            newBout=Button("New bout · N",NewBout,"arena-new-bout");newBout.style.height=44;moves.Add(newBout);bottom.Add(moves);
            rivalActions=Row();rivalActions.style.marginTop=6;
            rivalPulse=Button("J   P2 PULSE",()=>PlaySeat(ArenaSeat.Two,ArenaMove.Pulse),"arena-p2-pulse",true);
            rivalGuard=Button("K   P2 GUARD",()=>PlaySeat(ArenaSeat.Two,ArenaMove.Guard),"arena-p2-guard",true);
            rivalSignature=Button("L   P2 SIGNATURE",()=>PlaySeat(ArenaSeat.Two,ArenaMove.Signature),"arena-p2-signature",true);
            foreach(var button in new[]{rivalPulse,rivalGuard,rivalSignature}){button.style.flexGrow=1;button.style.height=36;rivalActions.Add(button);}
            bottom.Add(rivalActions);
            multiplayerStatus=Text("",11,Mint);bottom.Add(multiplayerStatus);
            feedback=Text(Bout.Feedback,11,Muted);feedback.name="arena-feedback";feedback.style.marginTop=8;bottom.Add(feedback);
            bottom.Add(Text("Practice is temporary · saved KIN, lessons and evolution remain in the native app",10,Muted));overlay.Add(bottom);
            lawDetails=Panel("arena-law-details");Absolute(lawDetails,30,30,145,22);lawDetails.style.backgroundColor=new Color(.025f,.045f,.055f,.99f);lawDetails.style.display=DisplayStyle.None;
            var lawHeader=Row();lawHeader.Add(Text("Laws of becoming · v1",24,Ink,true));var lawFill=new VisualElement();lawFill.style.flexGrow=1;lawHeader.Add(lawFill);
            lawHeader.Add(Button("Return to practice",ToggleLaws,"arena-laws-close"));lawDetails.Add(lawHeader);
            var lawScroll=new ScrollView(ScrollViewMode.Vertical);lawScroll.style.flexGrow=1;lawScroll.style.minHeight=0;StyleScroll(lawScroll);
            foreach(var law in EvolutionLawbook.Load().laws){var lawTitle=Text(law.title,15,Gold,true);lawTitle.style.marginTop=14;lawScroll.Add(lawTitle);var wording=Text(law.text,13,Ink);wording.style.marginTop=5;wording.style.marginBottom=12;lawScroll.Add(wording);}
            lawDetails.Add(lawScroll);overlay.Add(lawDetails);
            Refresh();overlay.Focus();
        }

        /// Native identity is a projection, never an Arena save. A local roster
        /// session has no identity and may use the existing disposable studies.
        public void ApplyNativePresentation(NativePresentationSnapshot value,bool staticMotion)
        {
            nativeBound=true;nativeIdentity=!value.LocalPractice;nativeName=value.displayName;
            nativeInputAllowed=value.active&&value.visible;
            nativeMotionPolicy=staticMotion;
            ReducedMotion=nativeMotionPolicy||locallyStill;Stage.StaticMotion=ReducedMotion;
            if(nativeIdentity){
                bool proto=value.Appearance=="proto";
                bool expressionChanged=Stage.ProtoSelected!=proto;
                if(expressionChanged)Stage.SelectProto(proto);
                Stage.SetSeedAppearance(value.SeedAppearance);
                bool target=value.body=="firstLight";
                if(body!=target||expressionChanged){body=target;Stage.SetForm(body);}
                Stage.ApplyNativeSeed(value);
                var badge=seedReference.Q<Image>();if(badge!=null)badge.image=SeedAppearanceRendering.Texture(value);
                Stage.SetStaff(value.equippedFocusStaff);
                Stage.SetStaffRecipe(value.staffPalette,value.staffCrown);
                Stage.SetMantle(false);
            }
            if(ReducedMotion||!nativeInputAllowed)Stage.Stop();
            Refresh();
        }

        public bool Play(ArenaMove move)
        {
            if(!NativeInputAllowed || Stage.Busy || resting || LawsOpen)return false;
            if(TwoPlayers)return PlaySeat(ArenaSeat.One,move);
            if(!Bout.Resolve(move,Bout.Round))return false;
            activityRounds++;Stage.Perform(Bout);Refresh();return true;
        }
        public void NewBout(){if(!NativeInputAllowed)return;Stage.Stop();ResetBout(Bout.Field);resting=false;Refresh();}
        private void ResetBout(ArenaField fieldValue) {
            if(TwoPlayers){Multiplayer=new ArenaMultiplayerSession(Guid.NewGuid().ToString(),fieldValue,"player-one","player-two");Bout=Multiplayer.Bout;}
            else Bout=new ArenaRehearsal(fieldValue);
        }
        public void ToggleTwoPlayers() {
            if(!NativeInputAllowed||Stage.Busy||LawsOpen)return;
            Stage.Stop();
            Multiplayer=TwoPlayers?null:new ArenaMultiplayerSession(Guid.NewGuid().ToString(),Bout.Field,"player-one","player-two");
            Bout=Multiplayer?.Bout??new ArenaRehearsal(Bout.Field);
            Learning=new ArenaLearningPreview();activityRounds=0;resting=false;Refresh();
        }
        public bool PlaySeat(ArenaSeat seat,ArenaMove move) {
            if(!TwoPlayers||!NativeInputAllowed||Stage.Busy||resting||LawsOpen)return false;
            var result=Multiplayer.Submit(seat,Multiplayer.CreateCommand(seat,move));
            if(result.Resolved){activityRounds++;Stage.Perform(Bout);}
            Refresh();return result.Accepted;
        }
        public void ToggleField(){if(!NativeInputAllowed)return;Stage.Stop();ResetBout(Bout.Field==ArenaField.Guardian?ArenaField.Scout:ArenaField.Guardian);resting=false;Refresh();}
        public bool Review(){if(!NativeInputAllowed||TwoPlayers)return false;var kept=Learning.Review(Bout);Refresh();return kept;}
        public void ToggleCharacter()
        {
            if(nativeIdentity||!NativeInputAllowed||Stage.Busy||LawsOpen)return;
            Stage.SelectProto(!ProtoSelected);body=true;resting=false;activityRounds=0;
            ResetBout(Bout.Field);Learning=new ArenaLearningPreview();Refresh();
        }
        public void ToggleLaws(){LawsOpen=!LawsOpen;if(LawsOpen)Stage.Stop();lawDetails.style.display=LawsOpen?DisplayStyle.Flex:DisplayStyle.None;Refresh();}
        public void ToggleForm(){if(nativeIdentity||!NativeInputAllowed||Stage.Busy)return;body=!body;Stage.SetForm(body);Refresh();}
        public void ToggleStaff(){if(nativeIdentity||!NativeInputAllowed)return;Stage.SetStaff(!Stage.StaffEquipped);Refresh();}
        public void ToggleMantle(){if(nativeIdentity||!NativeInputAllowed)return;Stage.SetMantle(!Stage.MantleEquipped);Refresh();}
        public void Rest(){if(!NativeInputAllowed)return;Stage.Recover();activityRounds=0;resting=!resting;Refresh();}
        public void ToggleMotion(){
            if(nativeBound){locallyStill=!locallyStill;ReducedMotion=nativeMotionPolicy||locallyStill;}
            else ReducedMotion=!ReducedMotion;
            Stage.StaticMotion=ReducedMotion;if(ReducedMotion)Stage.Stop();Refresh();
        }
        public void Stop(){if(nativeBound){locallyStill=true;ReducedMotion=true;Stage.StaticMotion=true;}Stage.Stop();Refresh();}
        public void Close(){ReleaseView();gameObject.SetActive(false);Destroy(gameObject);}
        private void Update(){if(Stage==null)return;if(wasBusy!=Stage.Busy){wasBusy=Stage.Busy;Refresh();}}
        private void Refresh()
        {
            if(overlay==null)return;
            round.text=Bout.Complete?(Bout.Winner=="draw"?"DRAW":Bout.Winner=="one"?CharacterName.ToUpperInvariant()+" PREVAILS":(TwoPlayers?"PLAYER TWO PREVAILS":"ECHO PREVAILS")):$"ROUND {Bout.Round:00}";
            fieldLabel.text=$"{CharacterName} · {Bout.Field} field";kinValue.text=$"{Bout.Integrity} / 36";rivalValue.text=$"{Bout.RivalIntegrity} / 36";
            kinBar.style.width=Length.Percent(Bout.Integrity/36f*100);rivalBar.style.width=Length.Percent(Bout.RivalIntegrity/36f*100);
            bool canPlay=NativeInputAllowed&&!Stage.Busy&&!Bout.Complete&&!resting&&!LawsOpen;
            bool oneReady=TwoPlayers&&Multiplayer.HasPending(ArenaSeat.One);
            bool twoReady=TwoPlayers&&Multiplayer.HasPending(ArenaSeat.Two);
            pulse.SetEnabled(canPlay&&!oneReady);guard.SetEnabled(canPlay&&!oneReady);signature.SetEnabled(canPlay&&!oneReady&&Bout.Spark>0);
            rivalPulse.SetEnabled(canPlay&&!twoReady);rivalGuard.SetEnabled(canPlay&&!twoReady);rivalSignature.SetEnabled(canPlay&&!twoReady&&Bout.RivalSpark>0);
            rivalSignature.text=$"L   P2 SIGNATURE / {Bout.RivalSpark}";
            rivalActions.style.display=TwoPlayers?DisplayStyle.Flex:DisplayStyle.None;
            rivalName.text=TwoPlayers?"PLAYER TWO · guest ECHO":"ECHO · practice partner";
            modeButton.text=TwoPlayers?"Solo practice · M":"2 players · M";modeButton.SetEnabled(NativeInputAllowed&&!Stage.Busy&&!LawsOpen);
            multiplayerStatus.style.display=TwoPlayers?DisplayStyle.Flex:DisplayStyle.None;
            multiplayerStatus.text=Bout.Complete?"Local match finished · New bout to play again":$"Same Mac · P1 {(oneReady?"ready":"choose 1 / 2 / 3")} · P2 {(twoReady?"ready":"choose J / K / L")} · moves reveal together";
            signature.text=$"3   SIGNATURE  /  {Bout.Spark} spark";
            field.text=Bout.Field==ArenaField.Guardian?"Train Scout field":"Train Guardian field";
            review.SetEnabled(!TwoPlayers&&Bout.Complete&&!Stage.Busy);review.text=Learning.ReviewedBouts>0?$"Review · {Learning.ReviewedBouts} kept in session":"Review this experience";
            form.text=ProtoSelected?(body?"Gather into light":"Unfold light into Proto"):(body?"Gather into Core Seed":"Unfold into First Light");form.SetEnabled(!Stage.Busy);
            characterButton.text=ProtoSelected?"Study KIN · First Light":"Study OG Proto ARCHi";characterButton.SetEnabled(!Stage.Busy);
            if(nativeIdentity){
                form.text=body?"First Light · from ARCHi":Stage.SeedAppearance=="hamptonLiminal"?"Liminal Seed · from ARCHi":Stage.SeedAppearance=="archiLight"?"Ball of Light · from ARCHi":"Core Seed · from ARCHi";form.SetEnabled(false);
                characterButton.text=Stage.SeedAppearance=="hamptonLiminal"?"Authored Seed · from ARCHi":ProtoSelected?"Proto expression · from ARCHi":"KIN expression · from ARCHi";characterButton.SetEnabled(false);
            }
            overlay.Q<Label>("arena-identity-note").text=nativeIdentity?"Identity, body and items follow native ARCHi.":nativeBound?"Local roster study · no saved identity.":"A character study starts fresh practice.";
            beingName.text=CharacterName;
            seedReference.style.display=ProtoSelected&&!nativeIdentity?DisplayStyle.None:DisplayStyle.Flex;
            lesson.text=Learning.ReviewedBouts==0?"Practice produces experience. Review its meaning before keeping a lesson.":$"Guardian evidence {Learning.GuardianEvidence} · Scout evidence {Learning.ScoutEvidence}\n{Learning.Lesson}";
            staffButton.text=Stage.StaffEquipped?"Remove Focus Staff":"Equip Focus Staff";mantleButton.text=Stage.MantleEquipped?"Remove Starlight collar":"Wear Starlight collar";
            if(nativeIdentity)staffButton.text=Stage.StaffEquipped?"Focus Staff · from ARCHi":"No staff · from ARCHi";
            staffButton.SetEnabled(!nativeIdentity&&NativeInputAllowed);mantleButton.style.display=nativeIdentity?DisplayStyle.None:DisplayStyle.Flex;
            motionButton.text=ReducedMotion?"Motion: still":"Motion: full";
            if(nativeBound){motionButton.text=nativeMotionPolicy?"Still · desktop setting":locallyStill?"Resume motion":"Pause motion";motionButton.SetEnabled(!nativeMotionPolicy);}
            readiness.text=resting?"Resting together · click Rest to return":activityRounds>5?"A pause is available. No absence penalty.":"Ready · choose your own pace";
            motion.text=resting?CharacterName+" / REST":Stage.Busy?$"{CharacterName} / {Stage.MotionName.ToUpperInvariant()}":CharacterName+" / OBSERVE";
            feedback.text=Bout.Feedback;
            if(TwoPlayers)lesson.text="Two human players · session-only match. Guest uses ECHO. Online pairing is not available yet.";
        }
        private void Key(KeyDownEvent e)
        {
            // App/system shortcuts must not also change a match (for example Cmd+N).
            if(e.commandKey||e.ctrlKey||e.altKey)return;
            if(e.keyCode==KeyCode.Alpha1)Play(ArenaMove.Pulse);
            else if(e.keyCode==KeyCode.Alpha2)Play(ArenaMove.Guard);
            else if(e.keyCode==KeyCode.Alpha3)Play(ArenaMove.Signature);
            else if(e.keyCode==KeyCode.P)ToggleCharacter();
            else if(e.keyCode==KeyCode.M)ToggleTwoPlayers();
            else if(e.keyCode==KeyCode.N){if(!LawsOpen)NewBout();}
            else if(e.keyCode==KeyCode.B)Close();
            else if(TwoPlayers&&e.keyCode==KeyCode.J)PlaySeat(ArenaSeat.Two,ArenaMove.Pulse);
            else if(TwoPlayers&&e.keyCode==KeyCode.K)PlaySeat(ArenaSeat.Two,ArenaMove.Guard);
            else if(TwoPlayers&&e.keyCode==KeyCode.L)PlaySeat(ArenaSeat.Two,ArenaMove.Signature);
            else if(e.keyCode==KeyCode.L)ToggleLaws();
            else if(e.keyCode==KeyCode.Escape){if(LawsOpen)ToggleLaws();else Stop();}else return;
            e.StopPropagation();
        }
        private void Layout(GeometryChangedEvent e){bool compact=e.newRect.width<1050;leftPanel.style.width=compact?170:200;rightPanel.style.width=compact?185:220;FitPanelsAboveActions();}
        private void FitPanelsAboveActions()
        {
            var actions=overlay?.Q<VisualElement>("arena-action-panel");
            if(actions==null||float.IsNaN(actions.layout.y)||actions.layout.y<=0)return;
            float bottom=overlay.layout.height-actions.layout.y+16;
            leftPanel.style.bottom=bottom;rightPanel.style.bottom=bottom;
        }
        public string LayoutReport()
        {
            var report=new System.Text.StringBuilder();
            foreach(var name in new[]{"arena-workspace","arena-action-panel","arena-evolution-panel","arena-pulse","arena-guard","arena-signature","arena-unfold","arena-close","arena-stop"}){
                var control=name=="arena-workspace"?overlay:overlay?.Q<VisualElement>(name);
                report.Append(name).Append(": ").Append(control==null?"missing":control.worldBound.ToString()).AppendLine();
            }
            return report.ToString();
        }
        public bool LayoutValid()
        {
            if(overlay==null)return false;var bounds=overlay.worldBound;
            foreach(var name in new[]{"arena-pulse","arena-guard","arena-signature","arena-unfold","arena-close","arena-stop"}){
                var control=overlay.Q<Button>(name);if(control==null||control.worldBound.width<20||control.worldBound.height<20||!bounds.Contains(control.worldBound.center))return false;
            }
            return !rightPanel.worldBound.Overlaps(overlay.Q<VisualElement>("arena-action-panel").worldBound);
        }
        private void ReleaseView()
        {
            if(viewReleased)return;viewReleased=true;nativeInputAllowed=false;Stage?.Stop();
            overlay?.UnregisterCallback<KeyDownEvent>(Key);overlay?.UnregisterCallback<GeometryChangedEvent>(Layout);overlay?.RemoveFromHierarchy();
            for(int i=0;i<hidden.Count;i++)hidden[i].style.display=displayStates[i];
            overlay=null;
            var close=onClose;onClose=null;close?.Invoke();
        }
        private void OnDestroy(){ReleaseView();}
        private static VisualElement Row(){var r=new VisualElement();r.style.flexDirection=FlexDirection.Row;return r;}
        private static void StyleScroll(ScrollView scroll)
        {
            scroll.verticalScroller.style.width=7;
            scroll.verticalScroller.style.minWidth=7;scroll.verticalScroller.style.maxWidth=7;
            scroll.verticalScroller.style.overflow=Overflow.Hidden;
            scroll.verticalScroller.lowButton.style.display=DisplayStyle.None;
            scroll.verticalScroller.highButton.style.display=DisplayStyle.None;
            scroll.verticalScroller.style.opacity=.4f;
        }
        private static Label Text(string text,int size,Color color,bool bold=false){var l=new Label(text);l.style.fontSize=size;l.style.color=color;l.style.whiteSpace=WhiteSpace.Normal;l.style.unityFontStyleAndWeight=bold?FontStyle.Bold:FontStyle.Normal;l.style.marginBottom=3;return l;}
        private static VisualElement Panel(string name){var p=new VisualElement{name=name};p.style.backgroundColor=new Color(.024f,.043f,.057f,.9f);p.style.paddingLeft=16;p.style.paddingRight=16;p.style.paddingTop=16;p.style.paddingBottom=16;p.style.borderTopWidth=1;p.style.borderTopColor=new Color(.36f,.44f,.43f,.5f);return p;}
        private static Button Button(string text,Action action,string name,bool emphasized=false){var b=new Button(action){text=text,name=name};b.style.height=32;b.style.marginTop=5;b.style.marginRight=5;b.style.fontSize=11;b.style.whiteSpace=WhiteSpace.Normal;b.style.backgroundColor=emphasized?new Color(.13f,.22f,.25f):new Color(.075f,.12f,.15f);b.style.color=emphasized?Ink:Muted;b.style.borderLeftWidth=0;b.style.borderRightWidth=0;b.style.borderTopWidth=0;b.style.borderBottomWidth=1;b.style.borderBottomColor=emphasized?Gold:new Color(.2f,.3f,.32f);b.style.borderTopLeftRadius=3;b.style.borderTopRightRadius=3;b.style.borderBottomLeftRadius=3;b.style.borderBottomRightRadius=3;return b;}
        private static VisualElement Bar(VisualElement parent,Color color){var track=new VisualElement();track.style.height=3;track.style.backgroundColor=new Color(.14f,.2f,.22f);var bar=new VisualElement();bar.style.height=3;bar.style.width=Length.Percent(100);bar.style.backgroundColor=color;track.Add(bar);parent.Add(track);return bar;}
        private static void Absolute(VisualElement v,float left,float right,float top,float bottom){v.style.position=Position.Absolute;if(!float.IsNaN(left))v.style.left=left;if(!float.IsNaN(right))v.style.right=right;if(!float.IsNaN(top))v.style.top=top;if(!float.IsNaN(bottom))v.style.bottom=bottom;}
    }
}
