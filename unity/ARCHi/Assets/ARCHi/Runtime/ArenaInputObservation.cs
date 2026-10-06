using System;
using UnityEngine;
using UnityEngine.UIElements;

namespace ARCHi.Port
{
    /// <summary>Opt-in, local input diagnostics. No input synthesis or saved-state writes.</summary>
    public sealed class ArenaInputObservation : MonoBehaviour
    {
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        private static void Launch()
        {
            if(Application.isEditor||Array.IndexOf(Environment.GetCommandLineArgs(),"-archiObserveInput")<0)return;
            new GameObject("Explicit input observation").AddComponent<ArenaInputObservation>();
        }
        private void Start()
        {
            var document=UnityEngine.Object.FindAnyObjectByType<UIDocument>();
            document.rootVisualElement.RegisterCallback<PointerDownEvent>(e=>Debug.Log("ARCHI_INPUT pointer "+e.position+" target="+((VisualElement)e.target).name),TrickleDown.TrickleDown);
            document.rootVisualElement.RegisterCallback<KeyDownEvent>(e=>Debug.Log("ARCHI_INPUT key "+e.keyCode),TrickleDown.TrickleDown);
        }
        private void Update()
        {
            if(Input.GetMouseButtonDown(0))Debug.Log("ARCHI_INPUT mouse="+Input.mousePosition+" focused="+Application.isFocused);
            if(Input.anyKeyDown)Debug.Log("ARCHI_INPUT activity focused="+Application.isFocused);
        }
    }
}
