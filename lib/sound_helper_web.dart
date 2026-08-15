import 'dart:js' as js;

void playPlatformScannerBeep() {
  try {
    js.context.callMethod('eval', [
      """
      (function() {
        try {
          var AudioContextClass = window.AudioContext || window.webkitAudioContext;
          if (!AudioContextClass) return;

          // Initialize global AudioContext if not already done
          if (!window._scannerAudioCtx) {
            window._scannerAudioCtx = new AudioContextClass();
          }

          var ctx = window._scannerAudioCtx;

          // Global unlocker logic to handle browser Autoplay policy restricts
          if (!window._scannerUnlocked) {
            window._scannerUnlocked = true;
            
            var resumeAudio = function() {
              if (ctx && ctx.state === 'suspended') {
                ctx.resume().then(function() {
                  console.log("Scanner AudioContext successfully unlocked and resumed.");
                }).catch(function(err) {
                  console.warn("Unlocking AudioContext failed:", err);
                });
              }
            };

            // Register global interaction triggers to auto-resume audio
            window.addEventListener('click', resumeAudio, { capture: true, once: false, passive: true });
            window.addEventListener('touchstart', resumeAudio, { capture: true, once: false, passive: true });
            window.addEventListener('keydown', resumeAudio, { capture: true, once: false, passive: true });
            
            // Try to resume immediately in case we're in a gesture callback context
            resumeAudio();
          }

          if (!ctx) return;
          
          // Force resume if it got suspended
          if (ctx.state === 'suspended') {
            ctx.resume();
          }

          // Create dynamic beep sound using Oscillator
          var oscillator = ctx.createOscillator();
          var gainNode = ctx.createGain();
          
          oscillator.connect(gainNode);
          gainNode.connect(ctx.destination);
          
          oscillator.type = 'sine';
          // Standard scanner beep at 1350Hz - 1400Hz frequency
          oscillator.frequency.setValueAtTime(1380, ctx.currentTime);
          
          gainNode.gain.setValueAtTime(0, ctx.currentTime);
          gainNode.gain.linearRampToValueAtTime(0.25, ctx.currentTime + 0.01); // Crisp onset
          gainNode.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + 0.12); // Short 120ms beep decay
          
          oscillator.start(ctx.currentTime);
          oscillator.stop(ctx.currentTime + 0.13);
        } catch(e) {
          console.warn("Unable to play scanner scan beep on Web:", e);
        }
      })()
    """
    ]);
  } catch (e) {
    // Ignore Dart context failures
  }
}
