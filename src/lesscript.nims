--mm:arc
--app:console
--define:useMalloc
--define:nimPreviewHashRef

when defined release:
  --opt:speed
  --checks:off
  --passC:"-flto"
  --define:danger
  --define:nimAllocPagesViaMalloc