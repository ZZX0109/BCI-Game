using FirstPersonSokoban.Presentation;
using UnityEngine;

namespace FirstPersonSokoban.Interaction
{
    /// <summary>瞄准箱子时，在「箱子将被推入的格子」显示一块地面标记。</summary>
    public sealed class PushPreviewView : MonoBehaviour
    {
        private Material previewMaterial;

        public static PushPreviewView Create(Transform parent)
        {
            var root = new GameObject("Push Target Preview");
            root.transform.SetParent(parent, false);
            PushPreviewView view = root.AddComponent<PushPreviewView>();
            view.Build();
            root.SetActive(false);
            return view;
        }

        private void Build()
        {
            GameObject plate = GameObject.CreatePrimitive(PrimitiveType.Cube);
            plate.name = "Target Cell Plate";
            Collider collider = plate.GetComponent<Collider>();
            if (collider != null) { collider.enabled = false; Destroy(collider); }
            plate.transform.SetParent(transform, false);
            plate.transform.localScale = new Vector3(1.72f, 0.03f, 1.72f);

            Shader shader = Shader.Find("Standard");
            previewMaterial = shader != null ? new Material(shader) : null;
            if (previewMaterial != null)
            {
                previewMaterial.name = "Sokoban Push Preview (Runtime)";
                previewMaterial.color = LabMaterials.Hex("D9BC8E");
                plate.GetComponent<Renderer>().sharedMaterial = previewMaterial;
            }
        }

        private void OnDestroy()
        {
            if (previewMaterial != null) Destroy(previewMaterial);
        }

        public void Show(Vector3 cellWorld)
        {
            transform.position = cellWorld + Vector3.up * 0.04f;
            gameObject.SetActive(true);
        }

        public void Hide() => gameObject.SetActive(false);
    }
}
