using System.Collections;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.UI;

namespace FirstPersonSokoban.Presentation
{
    /// <summary>
    /// A real 3D equipment still for the menu. Rendering happens once, never in Update.
    /// The independent stage has no physics and is disabled immediately after capture.
    /// </summary>
    public sealed class LabPreviewView : MonoBehaviour
    {
        private const int PreviewLayer = 31;
        private const int PreviewMask = 1 << PreviewLayer;
        private RawImage image;
        private GameObject stage;
        private Camera previewCamera;
        private RenderTexture target;
        private Coroutine capture;
        private bool configured;

        public bool IsRendered { get; private set; }

        public static LabPreviewView Attach(RectTransform parent)
        {
            LabPreviewView existing = parent.GetComponent<LabPreviewView>();
            if (existing != null) return existing;
            LabPreviewView view = parent.gameObject.AddComponent<LabPreviewView>();
            view.Configure();
            return view;
        }

        private void Configure()
        {
            var graphic = new GameObject("Equipment Image", typeof(RectTransform), typeof(RawImage), typeof(AspectRatioFitter));
            graphic.transform.SetParent(transform, false);
            var fit = graphic.GetComponent<AspectRatioFitter>();
            fit.aspectMode = AspectRatioFitter.AspectMode.FitInParent;
            fit.aspectRatio = 1024f / 288f;
            image = graphic.GetComponent<RawImage>();
            image.raycastTarget = false;
            // This path also works in headless tests: do not allocate GPU targets there.
            if (Application.isBatchMode || SystemInfo.graphicsDeviceType == GraphicsDeviceType.Null)
            {
                image.enabled = false;
                configured = true;
                return;
            }

            target = new RenderTexture(1024, 288, 16, RenderTextureFormat.ARGB32)
            {
                name = "Lab Menu Equipment Preview",
                antiAliasing = 2,
                wrapMode = TextureWrapMode.Clamp,
                useMipMap = false,
                autoGenerateMips = false
            };
            target.Create();
            image.texture = target;
            image.color = Color.white;
            image.enabled = false;

            // Keep the stage outside the scaled Canvas hierarchy. It is owned here,
            // so it is still destroyed when this view is destroyed or the scene exits.
            stage = new GameObject("Lab Menu Preview Stage") { layer = PreviewLayer };
            stage.transform.position = new Vector3(10000f, 10000f, 10000f);
            LabMaterials materials = stage.AddComponent<LabMaterials>();
            materials.Initialize();
            BuildEquipment(materials);
            BuildCamera();
            stage.SetActive(false);
            configured = true;
            if (isActiveAndEnabled) capture = StartCoroutine(CaptureOnce());
        }

        private void OnEnable()
        {
            if (configured && stage != null && !IsRendered && capture == null)
                capture = StartCoroutine(CaptureOnce());
        }

        private void OnDisable()
        {
            if (capture != null) StopCoroutine(capture);
            capture = null;
            if (stage != null) stage.SetActive(false);
        }

        private IEnumerator CaptureOnce()
        {
            yield return null;
            capture = null;
            if (stage == null || previewCamera == null || target == null) yield break;
            stage.SetActive(true);
            try
            {
                previewCamera.Render();
                IsRendered = true;
                if (image != null) image.enabled = true;
            }
            finally
            {
                // No preview lights, renderers or camera remain active during play.
                if (stage != null) stage.SetActive(false);
            }
        }

        private void BuildCamera()
        {
            GameObject cameraObject = Child("Equipment Camera");
            previewCamera = cameraObject.AddComponent<Camera>();
            previewCamera.enabled = false;
            previewCamera.cullingMask = PreviewMask;
            previewCamera.clearFlags = CameraClearFlags.SolidColor;
            previewCamera.backgroundColor = new Color(0.965f, 0.937f, 0.890f, 0f);
            previewCamera.orthographic = true;
            previewCamera.orthographicSize = 1.9f;
            previewCamera.aspect = (float)target.width / target.height;
            previewCamera.nearClipPlane = 0.1f;
            previewCamera.farClipPlane = 35f;
            previewCamera.allowHDR = false;
            previewCamera.allowMSAA = true;
            previewCamera.targetTexture = target;
            cameraObject.transform.localPosition = new Vector3(6.5f, 4.6f, -7.6f);
            cameraObject.transform.LookAt(stage.transform.position + new Vector3(0f, 0.70f, 0.25f));
        }

        private void BuildEquipment(LabMaterials materials)
        {
            Cube("Training Room Floor", new Vector3(0f, -0.12f, 0f), new Vector3(8.6f, 0.16f, 5.5f), materials.Floor);
            Cube("Rear Panel", new Vector3(0f, 1.25f, 2.70f), new Vector3(8.6f, 2.8f, 0.10f), materials.Wall);
            Cube("Rear Skirting", new Vector3(0f, 0.10f, 2.62f), new Vector3(8.6f, 0.20f, 0.10f), materials.Trim);
            Cube("Rear Light Recess", new Vector3(0f, 2.46f, 2.61f), new Vector3(6.5f, 0.15f, 0.08f), materials.Dark);
            Cube("Rear Linear Light", new Vector3(0f, 2.46f, 2.55f), new Vector3(6.25f, 0.045f, 0.035f), materials.Light);
            for (int i = -2; i <= 2; i++)
            {
                Cube("Floor Seam X", new Vector3(i * 2f, -0.032f, 0f), new Vector3(0.018f, 0.005f, 5.5f), materials.Trim);
                Cube("Wall Panel Seam", new Vector3(i * 2f, 1.36f, 2.635f), new Vector3(0.012f, 2.1f, 0.008f), materials.Trim);
            }
            for (int i = -1; i <= 1; i++)
                Cube("Floor Seam Z", new Vector3(0f, -0.032f, i * 2f), new Vector3(8.6f, 0.005f, 0.018f), materials.Trim);

            Vector3 module = new Vector3(-1.35f, 0f, 0f);
            Platform(module, materials);
            Cube("Training Module Shell", module + new Vector3(0f, 0.84f, 0f), new Vector3(1.88f, 1.62f, 1.88f), materials.Module);
            Cube("Module Top Inset", module + new Vector3(0f, 1.66f, 0f), new Vector3(1.61f, 0.035f, 1.61f), materials.Dark);
            Cube("Module Top Panel", module + new Vector3(0f, 1.68f, 0f), new Vector3(1.48f, 0.025f, 1.48f), materials.Module);
            Cube("Module Bottom Frame", module + new Vector3(0f, 0.12f, 0f), new Vector3(1.95f, 0.18f, 1.95f), materials.Dark);
            for (int x = -1; x <= 1; x += 2)
            for (int z = -1; z <= 1; z += 2)
                Cube("Module Protective Corner", module + new Vector3(x * 0.91f, 0.88f, z * 0.91f),
                    new Vector3(0.12f, 1.42f, 0.12f), materials.Trim);
            Cube("Module Handle Recess", module + new Vector3(0f, 1.20f, -0.947f), new Vector3(0.65f, 0.17f, 0.018f), materials.Dark);
            Cube("Module Handle Grip", module + new Vector3(0f, 1.23f, -0.961f), new Vector3(0.48f, 0.035f, 0.028f), materials.Metal);
            Cube("Module Status Strip", module + new Vector3(0f, 0.84f, -0.952f), new Vector3(0.42f, 0.045f, 0.018f), materials.GoalActive);
            Cube("Module ID Plate", module + new Vector3(0.48f, 0.36f, -0.952f), new Vector3(0.38f, 0.17f, 0.018f), materials.Dark);
            Platform(new Vector3(1.60f, 0f, 0.12f), materials);

            GameObject keyObject = Child("Preview Key Light");
            Light key = keyObject.AddComponent<Light>();
            key.type = LightType.Directional;
            key.cullingMask = PreviewMask;
            key.color = LabMaterials.Hex("FFF1DB");
            key.intensity = 1.15f;
            key.shadows = LightShadows.None;
            keyObject.transform.localRotation = Quaternion.Euler(48f, -30f, 0f);
            GameObject fillObject = Child("Preview Warm Fill");
            Light fill = fillObject.AddComponent<Light>();
            fill.type = LightType.Point;
            fill.cullingMask = PreviewMask;
            fill.color = LabMaterials.Hex("FFE8CC");
            fill.intensity = 1.5f;
            fill.range = 11f;
            fill.shadows = LightShadows.None;
            fillObject.transform.localPosition = new Vector3(-4f, 2.8f, -2f);
        }

        private void Platform(Vector3 origin, LabMaterials materials)
        {
            Cube("Sensor Platform", origin + new Vector3(0f, 0f, 0f), new Vector3(2.14f, 0.07f, 2.14f), materials.Dark);
            Cube("Sensor Inset", origin + new Vector3(0f, 0.039f, 0f), new Vector3(1.91f, 0.012f, 1.91f), materials.Trim);
            for (int side = -1; side <= 1; side += 2)
            {
                Cube("Sensor Track X", origin + new Vector3(0f, 0.05f, side * 1.01f), new Vector3(1.78f, 0.025f, 0.035f), materials.GoalActive);
                Cube("Sensor Track Z", origin + new Vector3(side * 1.01f, 0.05f, 0f), new Vector3(0.035f, 0.025f, 1.78f), materials.GoalActive);
            }
        }

        private GameObject Child(string name)
        {
            var child = new GameObject(name) { layer = PreviewLayer };
            child.transform.SetParent(stage.transform, false);
            return child;
        }

        private void Cube(string name, Vector3 position, Vector3 scale, Material material)
        {
            GameObject part = GameObject.CreatePrimitive(PrimitiveType.Cube);
            part.name = name;
            part.layer = PreviewLayer;
            Collider collider = part.GetComponent<Collider>();
            if (collider != null) { collider.enabled = false; Destroy(collider); }
            part.transform.SetParent(stage.transform, false);
            part.transform.localPosition = position;
            part.transform.localScale = scale;
            MeshRenderer renderer = part.GetComponent<MeshRenderer>();
            renderer.sharedMaterial = material;
            renderer.shadowCastingMode = ShadowCastingMode.Off;
            renderer.receiveShadows = false;
            renderer.lightProbeUsage = LightProbeUsage.Off;
            renderer.reflectionProbeUsage = ReflectionProbeUsage.Off;
        }

        private void OnDestroy()
        {
            if (capture != null) StopCoroutine(capture);
            if (previewCamera != null) previewCamera.targetTexture = null;
            if (image != null) image.texture = null;
            if (target != null)
            {
                target.Release();
                Destroy(target);
            }
            if (stage != null) Destroy(stage);
        }
    }
}
