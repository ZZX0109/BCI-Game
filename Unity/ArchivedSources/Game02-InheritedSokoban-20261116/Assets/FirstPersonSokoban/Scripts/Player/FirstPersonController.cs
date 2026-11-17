using FirstPersonSokoban.Core;
using UnityEngine;

namespace FirstPersonSokoban.PlayerSystem
{
    [RequireComponent(typeof(CharacterController))]
    public sealed class FirstPersonController : MonoBehaviour
    {
        [SerializeField] private float moveSpeed = 3.5f;
        [SerializeField] private float gravity = -22f;
        [SerializeField, Min(0.1f)] private float cameraHeight = 1.65f;

        private CharacterController characterController;
        private Camera playerCamera;
        private float verticalVelocity;
        private float pitch;
        private float sensitivity = 2.2f;
        private bool invertY;

        public Camera PlayerCamera => playerCamera;
        public bool InputLocked { get; private set; }
        /// <summary>Total horizontal movement, including push follow-through; teleports/undo are excluded.</summary>
        public float DistanceTravelled { get; private set; }
        public float CameraHeight => cameraHeight;
        public float LookYaw => transform.eulerAngles.y;
        public float LookPitch => pitch;

        private void Awake()
        {
            characterController = GetComponent<CharacterController>();
            playerCamera = GetComponentInChildren<Camera>(true);
            ApplyCameraHeight();
        }

        private void OnValidate()
        {
            cameraHeight = Mathf.Max(0.1f, cameraHeight);
            ApplyCameraHeight();
        }

        private void ApplyCameraHeight()
        {
            if (playerCamera == null) playerCamera = GetComponentInChildren<Camera>(true);
            if (playerCamera == null) return;
            Vector3 position = playerCamera.transform.localPosition;
            position.y = cameraHeight;
            playerCamera.transform.localPosition = position;
        }

        private void OnEnable()
        {
            GameSettings.Changed += ApplySettings;
            ApplySettings();
        }

        private void OnDisable() => GameSettings.Changed -= ApplySettings;

        private void ApplySettings()
        {
            sensitivity = GameSettings.MouseSensitivity;
            invertY = GameSettings.InvertY;
            if (playerCamera != null) playerCamera.fieldOfView = GameSettings.FieldOfView;
        }

        private void Update()
        {
            if (InputLocked || playerCamera == null) return;

            float yaw = Input.GetAxisRaw("Mouse X") * sensitivity;
            float lookY = Input.GetAxisRaw("Mouse Y") * sensitivity * (invertY ? -1f : 1f);
            transform.Rotate(0f, yaw, 0f);
            SetLookPitch(pitch - lookY);

            float horizontal = Input.GetAxisRaw("Horizontal");
            float vertical = Input.GetAxisRaw("Vertical");
            Vector3 planar = Vector3.ClampMagnitude(transform.right * horizontal + transform.forward * vertical, 1f);

            if (characterController.isGrounded && verticalVelocity < 0f) verticalVelocity = -2f;
            verticalVelocity += gravity * Time.deltaTime;
            MoveAndMeasure((planar * moveSpeed + Vector3.up * verticalVelocity) * Time.deltaTime);
        }

        // 由外部（过场、撤销恢复或自动化测试）设置俯仰角。
        // 必须通过此接口修改，因为 Update() 每帧会按内部 pitch 重写相机朝向。
        public void SetLookPitch(float degrees)
        {
            pitch = Mathf.Clamp(degrees, -82f, 82f);
            if (playerCamera != null)
                playerCamera.transform.localRotation = Quaternion.Euler(pitch, 0f, 0f);
        }

        /// <summary>撤销时把 yaw / pitch 一起恢复，避免「人回到旧位置、视角却朝向别处」。</summary>
        public void SetLookRotation(float yaw, float pitchDegrees)
        {
            transform.rotation = Quaternion.Euler(0f, yaw, 0f);
            SetLookPitch(pitchDegrees);
        }

        public void SetInputLocked(bool locked)
        {
            InputLocked = locked;
        }

        public void Teleport(Vector3 position)
        {
            bool wasEnabled = characterController.enabled;
            characterController.enabled = false;
            transform.position = position;
            characterController.enabled = wasEnabled;
            verticalVelocity = 0f;
        }

        public void MoveControlled(Vector3 delta)
        {
            MoveAndMeasure(delta);
        }

        private void MoveAndMeasure(Vector3 delta)
        {
            Vector3 before = transform.position;
            characterController.Move(delta);
            Vector3 travelled = transform.position - before;
            travelled.y = 0f;
            DistanceTravelled += travelled.magnitude;
        }
    }
}
