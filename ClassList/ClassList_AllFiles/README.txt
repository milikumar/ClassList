CLASSLIST - ALL CODE

1_App_files     (11 files) -> go in the yellow "ClassList" folder in Xcode
2_Widget_files  (2 files)  -> go in the "ClassListWidgets" folder (the extension) - ONLY tick the ClassListWidgets target

Extra rule: StudyTimerAttributes.swift (in 1_App_files) must ALSO be ticked for the ClassListWidgets target
(click the file, press Cmd+Option+1, tick both ClassList and ClassListWidgets under Target Membership).

Other setup in Xcode (not code):
- ClassList target > Info tab > add "Supports Live Activities" = YES
- File > New > Target > Widget Extension, name it ClassListWidgets, tick "Include Live Activity",
  then delete the .swift files Xcode generates inside it before adding the 2 widget files.
- Set the same Team under Signing & Capabilities for both targets.
