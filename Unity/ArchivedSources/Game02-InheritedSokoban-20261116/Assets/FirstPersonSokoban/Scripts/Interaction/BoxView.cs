using System.Collections;
using FirstPersonSokoban.Presentation;
using UnityEngine;

namespace FirstPersonSokoban.Interaction
{
    public sealed class BoxView : MonoBehaviour
    {
        private Renderer bodyRenderer;
        private Material normalMaterial;
        private Material goalMaterial;
        private Material deniedMaterial;
        private Coroutine feedbackRoutine;
        private bool isOnGoal;
        private GameObject highlightCap;
        private Material highlightMaterial;
        private Mesh highlightMesh;
        private TrainingModuleVisual moduleVisual;

        public Vector2Int GridPosition { get; private set; }
        public bool IsHighlighted => highlightCap != null && highlightCap.activeSelf;

        private void Awake()
        {
            Transform body = transform.Find("Body");
            if (body != null) bodyRenderer = body.GetComponent<Renderer>();
        }

        public void Initialize(Vector2Int gridPosition, Material normal, Material onGoal, Material denied)
        {
            moduleVisual = GetComponent<TrainingModuleVisual>();
            GridPosition = gridPosition;
            normalMaterial = normal;
            goalMaterial = onGoal;
            deniedMaterial = denied;
            SetOnGoal(false);
            BuildHighlightCap();
        }

        /// <summary>A thin selection rim keeps the target clear without a large luminous top plate.</summary>
        private void BuildHighlightCap()
        {
            if (highlightCap != null || normalMaterial == null) return;
            GameObject cap = GameObject.CreatePrimitive(PrimitiveType.Cube);
            cap.name = "Aim Highlight Cap";
            Collider collider = cap.GetComponent<Collider>();
            if (collider != null) { collider.enabled = false; Destroy(collider); }
            cap.transform.SetParent(transform, false);
            cap.transform.localPosition = new Vector3(0f,
                BoxDimensions.BodyCenterY + BoxDimensions.BodyHeight * 0.5f + 0.012f, 0f);
            cap.transform.localScale = Vector3.one;
            Mesh cube = cap.GetComponent<MeshFilter>().sharedMesh;
            var parts = new CombineInstance[4];
            for (int i = 0; i < parts.Length; i++)
            {
                bool horizontal = i < 2;
                float edge = i % 2 == 0 ? -0.93f : 0.93f;
                parts[i] = new CombineInstance
                {
                    mesh = cube,
                    transform = Matrix4x4.TRS(horizontal ? new Vector3(0, 0, edge) : new Vector3(edge, 0, 0),
                        Quaternion.identity, horizontal ? new Vector3(1.90f, 0.012f, 0.018f) :
                            new Vector3(0.018f, 0.012f, 1.90f))
                };
            }
            highlightMesh = new Mesh { name = "Sokoban Selection Rim (Runtime)" };
            highlightMesh.CombineMeshes(parts);
            cap.GetComponent<MeshFilter>().sharedMesh = highlightMesh;
            highlightMaterial = new Material(normalMaterial)
            {
                name = "Sokoban Aim Highlight (Runtime)",
                color = LabMaterials.Hex("E1AB63")
            };
            highlightMaterial.EnableKeyword("_EMISSION");
            highlightMaterial.SetColor("_EmissionColor", LabMaterials.Hex("E1AB63") * 0.08f);
            cap.GetComponent<Renderer>().sharedMaterial = highlightMaterial;
            cap.SetActive(false);
            highlightCap = cap;
        }

        public void SetHighlighted(bool highlighted)
        {
            if (highlightCap != null) highlightCap.SetActive(highlighted);
            if (moduleVisual != null) moduleVisual.SetState(isOnGoal, highlighted);
        }

        public void SetGridPosition(Vector2Int position) => GridPosition = position;

        public void SetOnGoal(bool complete)
        {
            isOnGoal = complete;
            if (bodyRenderer != null) bodyRenderer.sharedMaterial = complete ? goalMaterial : normalMaterial;
            if (moduleVisual != null) moduleVisual.SetState(complete, IsHighlighted);
        }

        public void SnapTo(Vector3 position) => transform.position = position;

        private void OnDestroy()
        {
            // Only this instance owns the generated highlight. Resource materials stay shared.
            if (highlightMaterial != null) Destroy(highlightMaterial);
            if (highlightMesh != null) Destroy(highlightMesh);
        }

        public void FlashDenied()
        {
            if (feedbackRoutine != null) StopCoroutine(feedbackRoutine);
            feedbackRoutine = StartCoroutine(DeniedFeedback());
        }

        private IEnumerator DeniedFeedback()
        {
            if (bodyRenderer != null && deniedMaterial != null) bodyRenderer.sharedMaterial = deniedMaterial;
            if (moduleVisual != null) moduleVisual.SetDenied(true);
            yield return new WaitForSeconds(0.16f);
            if (moduleVisual != null) moduleVisual.SetDenied(false);
            SetOnGoal(isOnGoal);
            feedbackRoutine = null;
        }
    }
}
