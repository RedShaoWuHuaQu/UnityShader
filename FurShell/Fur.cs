using UnityEngine;

[ExecuteInEditMode]
public class Fur : MonoBehaviour
{
    private Mesh mesh;
    public Material mat;
    private int shellCount = 32;
    public int testVal = 0;

    private ComputeBuffer indexBuffer;
    private ComputeBuffer argsBuffer;
    private Bounds bound;

    private Matrix4x4[] matrices;
    private ComputeBuffer matrixBuffer;

    public Texture2D[] hairTexs;
    private Texture2DArray hairTex;

    //
    [Header("Swing")]
    public bool enableSwing = false;
    public float swingSpeed;
    public float swingLength;

    private void SetTexture2DArray()
    {
        hairTex = new Texture2DArray(512, 512, hairTexs.Length, hairTexs[0].format, true);

        for (int i = 0; i < hairTexs.Length; i++)
        {
            Graphics.CopyTexture(hairTexs[i], 0, 0, hairTex, i, 0);
        }

        mat.SetTexture("_HairTex", hairTex);
    }

    private void OnEnable()
    {
        mesh = GetComponent<MeshFilter>().sharedMesh;
        if (mesh != null)
        {
            UpdateBuffer();
            SetTexture2DArray();

            bound = mesh.bounds;
            bound.Expand(100f);
        }
    }

    private void OnValidate()
    {
        ReleaseBuffer();
        UpdateBuffer();
        SetTexture2DArray();
    }

    private void UpdateBuffer()
    {
        if (mesh != null)
        {
            if (indexBuffer == null)
            {
                indexBuffer = new ComputeBuffer(shellCount + 1, sizeof(int));

                int[] indexs = new int[shellCount + 1];
                for (int i = 0; i <= shellCount; i++)
                {
                    indexs[i] = i;
                }

                indexBuffer.SetData(indexs);
            }

            if (argsBuffer == null)
            {
                argsBuffer = new ComputeBuffer(1, 5 * sizeof(uint), ComputeBufferType.IndirectArguments);

                uint[] args = new uint[5];
                args[0] = (uint)mesh.GetIndexCount(0);
                args[1] = (uint)(shellCount + 1);
                args[2] = (uint)mesh.GetIndexStart(0);
                args[3] = (uint)mesh.GetBaseVertex(0);
                args[4] = 0;

                argsBuffer.SetData(args);
            }

            if (matrixBuffer == null)
            {
                matrixBuffer = new ComputeBuffer(1, 64);
                matrices = new Matrix4x4[1];
                matrices[0] = transform.localToWorldMatrix;
                matrixBuffer.SetData(matrices);
            }
        }
    }

    private void ReleaseBuffer()
    {
        if (indexBuffer != null)
        {
            indexBuffer.Release();
            indexBuffer = null;
        }
        if (argsBuffer != null)
        {
            argsBuffer.Release();
            argsBuffer = null;
        }
        if (matrixBuffer != null)
        {
            matrixBuffer.Release();
            matrixBuffer = null;
        }
    }

    [Header("Move Force")]
    public float smooth = 5f;
    private Vector3 lastPosition, currentPosition;
    private Vector3 forceDir = Vector3.zero;
    private float forcePower = 0;
    private bool lastPositionInit = false;
    private Vector3 velocity = Vector3.zero;

    private void GetMoveForce()
    {
        currentPosition = transform.position;

        if (lastPositionInit == true)
        {
            Vector3 delta = (currentPosition - lastPosition) / Time.deltaTime;

            //velocity是上一帧速度，delta是这一帧速度
            velocity = Vector3.Lerp(velocity, delta, Time.deltaTime * smooth);

            forceDir = velocity.normalized;
            forcePower = velocity.magnitude * 0.01f;
        }
        else
        {
            lastPosition = currentPosition;
            lastPositionInit = true;
        }

        mat.SetVector("_MoveForceDir", forceDir);
        mat.SetFloat("_MoveForcePower", forcePower);

        lastPosition = currentPosition;
    }

    private void MoveObj()
    {
        Vector3 moveDir = Vector3.up;
        float dis = Mathf.Sin(Time.time * swingSpeed) * swingLength;

        transform.position += moveDir * dis * Time.deltaTime;
    }

    private void Update()
    {
        GetMoveForce();
        if (enableSwing)
        {
            MoveObj();
        }

        matrices[0] = transform.localToWorldMatrix;
        matrixBuffer.SetData(matrices);
        mat.SetBuffer("_MatrixBuffer", matrixBuffer);
        mat.SetInt("_MaxShell", shellCount);
        mat.SetBuffer("_ShellIndexBuffer", indexBuffer);
        Graphics.DrawMeshInstancedIndirect(mesh, 0, mat, bound, argsBuffer);
    }

    private void OnDisable()
    {
        ReleaseBuffer();
    }
}
