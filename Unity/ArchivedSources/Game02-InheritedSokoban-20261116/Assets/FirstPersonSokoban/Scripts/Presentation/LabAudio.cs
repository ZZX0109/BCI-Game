using System.Collections.Generic;
using FirstPersonSokoban.Core;
using UnityEngine;

namespace FirstPersonSokoban.Presentation
{
    public enum SoundCue { Hover, Click, PanelOpen, Push, Denied, Goal, Victory, Warning, Undo, Reset }

    /// <summary>Quiet, self-contained feedback; no downloaded audio or global AudioListener changes.</summary>
    public sealed class LabAudio : MonoBehaviour
    {
        private const int SampleRate = 22050;
        private static LabAudio instance;
        private readonly Dictionary<SoundCue, AudioClip> clips = new Dictionary<SoundCue, AudioClip>();
        private AudioSource feedback;
        private AudioSource ambience;
        private AudioClip roomTone;
        private float lastHover = -1f;
        private float lastWarning = -10f;

        private void Awake()
        {
            if (instance != null && instance != this) { Destroy(this); return; }
            instance = this;
            feedback = gameObject.AddComponent<AudioSource>();
            feedback.playOnAwake = false;
            feedback.spatialBlend = 0f;
            feedback.priority = 64;
            ambience = gameObject.AddComponent<AudioSource>();
            ambience.playOnAwake = false;
            ambience.spatialBlend = 0f;
            ambience.loop = true;
            ambience.priority = 180;
            ApplySettings();
        }

        private void OnEnable()
        {
            if (instance == this)
            {
                GameSettings.Changed += ApplySettings;
                ApplySettings();
            }
        }

        private void OnDisable()
        {
            GameSettings.Changed -= ApplySettings;
            if (ambience != null) ambience.Stop();
        }

        private void ApplySettings()
        {
            if (feedback == null || ambience == null) return;
            feedback.volume = GameSettings.MasterVolume;
            ambience.volume = GameSettings.MasterVolume * 0.055f;
            bool enabled = GameSettings.AmbientAudio && GameSettings.MasterVolume > 0f && !Application.isBatchMode;
            if (enabled && !ambience.isPlaying)
            {
                if (roomTone == null) roomTone = CreateRoomTone();
                ambience.clip = roomTone;
                ambience.Play();
            }
            else if (!enabled) ambience.Stop();
        }

        public static void Play(SoundCue cue)
        {
            if (instance == null || !instance.isActiveAndEnabled || Application.isBatchMode ||
                GameSettings.MasterVolume <= 0f) return;
            if (cue == SoundCue.Hover)
            {
                if (Time.unscaledTime - instance.lastHover < 0.10f) return;
                instance.lastHover = Time.unscaledTime;
            }
            if (cue == SoundCue.Warning)
            {
                if (Time.unscaledTime - instance.lastWarning < 1f) return;
                instance.lastWarning = Time.unscaledTime;
            }
            if (!instance.clips.TryGetValue(cue, out AudioClip clip))
            {
                clip = CreateCue(cue);
                instance.clips.Add(cue, clip);
            }
            float gain = cue == SoundCue.Hover ? 0.16f : cue == SoundCue.Push ? 0.52f : 0.42f;
            instance.feedback.PlayOneShot(clip, gain);
        }

        private static AudioClip CreateCue(SoundCue cue)
        {
            float duration = cue == SoundCue.Victory ? 0.48f : cue == SoundCue.Push ? 0.26f :
                cue == SoundCue.Goal ? 0.28f : cue == SoundCue.Warning ? 0.30f :
                cue == SoundCue.Hover ? 0.045f : 0.13f;
            var samples = new float[Mathf.CeilToInt(duration * SampleRate)];
            var random = new System.Random(1709 + (int)cue);
            float noise = 0f;
            for (int i = 0; i < samples.Length; i++)
            {
                float t = i / (float)SampleRate;
                float envelope = Mathf.Min(1f, t / 0.008f) * Mathf.Pow(1f - t / duration, 2f);
                noise = Mathf.Lerp(noise, (float)random.NextDouble() * 2f - 1f, 0.16f);
                float frequency;
                switch (cue)
                {
                    case SoundCue.Push: frequency = 78f + 38f * (1f - t / duration); break;
                    case SoundCue.Denied: frequency = 180f; break;
                    case SoundCue.Hover: frequency = 520f; break;
                    case SoundCue.Goal: frequency = t < 0.12f ? 440f : 660f; break;
                    case SoundCue.Victory: frequency = t < 0.15f ? 440f : t < 0.30f ? 554.37f : 659.25f; break;
                    case SoundCue.Warning: frequency = t < 0.15f ? 330f : 293.66f; break;
                    case SoundCue.Undo: frequency = 440f - 150f * t / duration; break;
                    case SoundCue.Reset: frequency = 220f + 150f * t / duration; break;
                    case SoundCue.PanelOpen: frequency = 320f; break;
                    default: frequency = 620f; break;
                }
                float tone = Mathf.Sin(2f * Mathf.PI * frequency * t);
                float body = cue == SoundCue.Push ? tone * 0.46f + noise * 0.44f : tone * 0.42f + noise * 0.05f;
                // Note changes have a short fade to avoid hard phase discontinuities.
                if (cue == SoundCue.Goal || cue == SoundCue.Victory || cue == SoundCue.Warning)
                {
                    float noteLength = cue == SoundCue.Goal ? 0.12f : 0.15f;
                    float position = t % noteLength;
                    envelope *= Mathf.Min(1f, Mathf.Min(position / 0.006f, (noteLength - position) / 0.012f));
                }
                samples[i] = Mathf.Clamp(body * envelope, -0.8f, 0.8f);
            }
            AudioClip clip = AudioClip.Create("Lab " + cue, samples.Length, 1, SampleRate, false);
            clip.SetData(samples, 0);
            return clip;
        }

        private static AudioClip CreateRoomTone()
        {
            var samples = new float[SampleRate * 2];
            var random = new System.Random(2007);
            float noise = 0f;
            for (int i = 0; i < samples.Length; i++)
            {
                float t = i / (float)SampleRate;
                noise = Mathf.Lerp(noise, (float)random.NextDouble() * 2f - 1f, 0.025f);
                float window = Mathf.Pow(Mathf.Sin(Mathf.PI * i / (samples.Length - 1f)), 2f);
                samples[i] = Mathf.Sin(2f * Mathf.PI * 60f * t) * 0.12f + noise * window * 0.35f;
            }
            AudioClip clip = AudioClip.Create("Lab room tone", samples.Length, 1, SampleRate, false);
            clip.SetData(samples, 0);
            return clip;
        }

        private void OnDestroy()
        {
            GameSettings.Changed -= ApplySettings;
            if (instance != this) return;
            instance = null;
            if (feedback != null) feedback.Stop();
            if (ambience != null) ambience.Stop();
            foreach (AudioClip clip in clips.Values) if (clip != null) Destroy(clip);
            clips.Clear();
            if (roomTone != null) Destroy(roomTone);
        }
    }
}
