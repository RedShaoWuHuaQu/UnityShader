using UnityEngine;

[ExecuteAlways]
public class UpdateFaceSDFDir : MonoBehaviour
{
    private Material currentMat;
    private Transform currentTrans;

    private Vector3 upDir;
    private Vector3 forwardDir;
    // Start is called before the first frame update
    void OnEnable()
    {
        currentMat = GetComponent<SkinnedMeshRenderer>().sharedMaterial;
        currentTrans = GetComponent<Transform>();
    }

    // Update is called once per frame
    void Update()
    {
        upDir = currentTrans.up;
        forwardDir = currentTrans.forward;

        currentMat.SetVector("_UpDir", upDir);
        currentMat.SetVector("_ForwardDir", forwardDir);
    }
}
