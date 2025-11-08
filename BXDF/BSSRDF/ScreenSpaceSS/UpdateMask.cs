using UnityEngine;

[ExecuteInEditMode]
public class UpdateMask : MonoBehaviour
{
    private void OnEnable()
    {
        ScreenSpaceSS.targetRenderer = this.GetComponent<Renderer>();
    }
}
