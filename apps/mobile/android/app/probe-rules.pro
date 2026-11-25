# Regeln nur fuer den R8-Mapping-Beweis (-PcrashProbe=true).
#
# Ohne diese Regel inlined R8 CrashProbe.trigger()/explode() in
# MainActivity.onCreate und entfernt die Klasse - der Stacktrace zeigt dann
# nur den gekeepten Activity-Namen und beweist nichts.
#
# allowobfuscation ist der Kern: Die Klasse bleibt mit ihren Frames erhalten,
# wird aber umbenannt. Genau darueber laesst sich das Mapping pruefen.
-keep,allowobfuscation class de.motoroute.probe.** { *; }
