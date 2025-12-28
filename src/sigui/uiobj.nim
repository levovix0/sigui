
when not defined(sigui_apply_uiobj_module_split):
  import ./[uiobjOnly, uiobjMacros]
  export uiobjOnly, uiobjMacros

  {.warning: "breaking change! uiobj module is beeng split into uiobj and uiobjMacros. Define -d:sigui_apply_uiobj_module_split to preview new behaviour".}
  # todo: remove old behaviour after 01.03.2026 or later

else:
  import ./uiobjOnly
  export uiobjOnly

