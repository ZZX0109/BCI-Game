using System.Collections.Generic;
using FirstPersonSokoban.PlayerSystem;
using UnityEngine;

namespace FirstPersonSokoban.Interaction
{
    public enum AimStatus
    {
        Ready,      // 已选中一个箱子（准星直击或小角度辅助）
        AimOff,     // 附近有箱子，但视线方向偏离
        TooFar,     // 箱子在交互距离之外
        Occluded,   // 视线被墙/其它遮挡物挡住
        NoTarget    // 视野内没有箱子
    }

    public readonly struct AimResult
    {
        public AimResult(AimStatus status, BoxView box, string hint)
        {
            Status = status;
            Box = box;
            Hint = hint;
        }

        public AimStatus Status { get; }
        public BoxView Box { get; }
        public string Hint { get; }
        public bool HasBox => Box != null;
    }

    public sealed class BoxInteractor : MonoBehaviour
    {
        [SerializeField] private float interactionDistance = 2.5f;
        // 32° 在多箱并排时会把旁边的箱子也吸进来。收紧到 14°，
        // 平视直接命中箱体（碰撞体顶高于眼高）仍不需要任何辅助。
        [SerializeField] private float assistAngle = 14f;
        [SerializeField] private float aimHeight = 0.9f;

        private const float AngleTieBreak = 1.5f;

        public float AssistAngleDegrees => assistAngle;

        private const int HitBufferSize = 32;
        private readonly RaycastHit[] hits = new RaycastHit[HitBufferSize];
        private readonly List<BoxView> knownBoxes = new List<BoxView>();
        private FirstPersonController player;

        private void Awake() => player = GetComponent<FirstPersonController>();

        /// <summary>由 LevelLoader 注入本关箱子，避免每帧 FindObjectsOfType 产生分配。</summary>
        public void SetBoxes(IReadOnlyList<BoxView> boxes)
        {
            knownBoxes.Clear();
            if (boxes == null) return;
            for (int i = 0; i < boxes.Count; i++)
                if (boxes[i] != null) knownBoxes.Add(boxes[i]);
        }

        public bool TryGetAimedBox(out BoxView box)
        {
            AimResult aim = EvaluateAim();
            box = aim.Box;
            return aim.HasBox;
        }

        /// <summary>
        /// 先用准星做一次 RaycastNonAlloc；若没命中箱子，再对小角度范围内的箱子
        /// 做「朝箱心射线」辅助选择。辅助射线同样取最近的非玩家命中，
        /// 因此墙仍然会遮挡，不允许隔墙选箱。
        /// </summary>
        public AimResult EvaluateAim()
        {
            if (player == null || player.PlayerCamera == null)
                return new AimResult(AimStatus.NoTarget, null, string.Empty);

            Transform eye = player.PlayerCamera.transform;
            Vector3 origin = eye.position;
            Vector3 forward = eye.forward;

            BoxView direct = FirstNonSelfBox(new Ray(origin, forward), interactionDistance,
                out float occluderDistance, out bool occludedBySolid);
            if (direct != null) return new AimResult(AimStatus.Ready, direct, string.Empty);

            BoxView best = null;
            float bestAngle = float.MaxValue;
            float bestDistance = float.MaxValue;
            float nearestBoxDistance = float.MaxValue;

            for (int i = 0; i < knownBoxes.Count; i++)
            {
                BoxView box = knownBoxes[i];
                if (box == null) continue;
                Vector3 to = box.transform.position + Vector3.up * aimHeight - origin;
                float distance = to.magnitude;
                if (distance < nearestBoxDistance) nearestBoxDistance = distance;
                if (distance > interactionDistance + 0.4f) continue;

                float angle = Vector3.Angle(forward, to);
                if (angle > assistAngle) continue;
                // 角度明显更小优先；角度接近时选更近的箱子，避免并排箱子误选远处那个。
                bool better = best == null ||
                              angle < bestAngle - AngleTieBreak ||
                              (Mathf.Abs(angle - bestAngle) <= AngleTieBreak &&
                               distance < bestDistance - 0.01f);
                if (!better) continue;

                BoxView candidate = FirstNonSelfBox(new Ray(origin, to.normalized),
                    distance + 0.08f, out float candidateOccluder, out _);
                if (candidate != box) continue;
                // 准星前方若有更近的实体遮挡，则不辅助选择（保持墙体遮挡语义）。
                if (occludedBySolid && occluderDistance < candidateOccluder - 0.05f) continue;

                best = box;
                bestAngle = angle;
                bestDistance = distance;
            }

            if (best != null) return new AimResult(AimStatus.Ready, best, string.Empty);

            if (knownBoxes.Count == 0)
                return new AimResult(AimStatus.NoTarget, null, string.Empty);
            if (nearestBoxDistance > interactionDistance + 0.4f)
                return new AimResult(AimStatus.TooFar, null, "靠近箱子到一格以内 · 再按 E");
            if (occludedBySolid)
                return new AimResult(AimStatus.Occluded, null, "视线被墙挡住了 · 绕到箱子这一侧");

            return new AimResult(AimStatus.AimOff, null, "低头或转头对准箱子正面 · 再按 E");
        }

        /// <summary>取射线上最近的「非玩家自身」命中；返回它是否是箱子以及遮挡距离。</summary>
        private BoxView FirstNonSelfBox(Ray ray, float maxDistance, out float firstDistance,
            out bool solidOccluder)
        {
            firstDistance = float.MaxValue;
            solidOccluder = false;
            int count = Physics.RaycastNonAlloc(ray, hits, maxDistance, ~0, QueryTriggerInteraction.Ignore);

            float nearest = float.MaxValue;
            int nearestIndex = -1;
            for (int i = 0; i < count; i++)
            {
                Transform target = hits[i].collider.transform;
                if (target == player.transform || target.IsChildOf(player.transform)) continue;
                if (hits[i].distance >= nearest) continue;
                nearest = hits[i].distance;
                nearestIndex = i;
            }

            if (nearestIndex < 0) return null;
            firstDistance = nearest;
            BoxView box = hits[nearestIndex].collider.GetComponentInParent<BoxView>();
            if (box == null) solidOccluder = true;
            return box;
        }
    }
}
