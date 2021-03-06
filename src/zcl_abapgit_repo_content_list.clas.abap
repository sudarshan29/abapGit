CLASS zcl_abapgit_repo_content_list DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    METHODS constructor
      IMPORTING io_repo TYPE REF TO zcl_abapgit_repo.

    METHODS list
      IMPORTING iv_path              TYPE string
                iv_by_folders        TYPE abap_bool
                iv_changes_only      TYPE abap_bool
      RETURNING VALUE(rt_repo_items) TYPE zif_abapgit_definitions=>tt_repo_items
      RAISING   zcx_abapgit_exception.

    METHODS get_log
      RETURNING VALUE(ro_log) TYPE REF TO zcl_abapgit_log.
  PRIVATE SECTION.
    CONSTANTS: BEGIN OF c_sortkey,
                 default    TYPE i VALUE 9999,
                 parent_dir TYPE i VALUE 0,
                 dir        TYPE i VALUE 1,
                 orphan     TYPE i VALUE 2,
                 changed    TYPE i VALUE 3,
                 inactive   TYPE i VALUE 4,
               END OF c_sortkey.

    DATA: mo_repo TYPE REF TO zcl_abapgit_repo,
          mo_log  TYPE REF TO zcl_abapgit_log.

    METHODS build_repo_items_offline
      RETURNING VALUE(rt_repo_items) TYPE zif_abapgit_definitions=>tt_repo_items
      RAISING   zcx_abapgit_exception.

    METHODS build_repo_items_online
      RETURNING VALUE(rt_repo_items) TYPE zif_abapgit_definitions=>tt_repo_items
      RAISING   zcx_abapgit_exception.

    METHODS build_folders
      IMPORTING iv_cur_dir    TYPE string
      CHANGING  ct_repo_items TYPE zif_abapgit_definitions=>tt_repo_items
      RAISING   zcx_abapgit_exception.

    METHODS filter_changes
      CHANGING ct_repo_items TYPE zif_abapgit_definitions=>tt_repo_items.
ENDCLASS.



CLASS ZCL_ABAPGIT_REPO_CONTENT_LIST IMPLEMENTATION.


  METHOD build_folders.

    DATA: lv_index    TYPE i,
          lt_subitems LIKE ct_repo_items,
          ls_subitem  LIKE LINE OF ct_repo_items,
          ls_folder   LIKE LINE OF ct_repo_items.

    FIELD-SYMBOLS <ls_item> LIKE LINE OF ct_repo_items.


    LOOP AT ct_repo_items ASSIGNING <ls_item>.
      lv_index = sy-tabix.
      CHECK <ls_item>-path <> iv_cur_dir. " files in target dir - just leave them be

      IF zcl_abapgit_path=>is_subdir( iv_path = <ls_item>-path  iv_parent = iv_cur_dir ) = abap_true.
        ls_subitem-changes = <ls_item>-changes.
        ls_subitem-path    = <ls_item>-path.
        ls_subitem-lstate  = <ls_item>-lstate.
        ls_subitem-rstate  = <ls_item>-rstate.
        APPEND ls_subitem TO lt_subitems.
      ENDIF.

      DELETE ct_repo_items INDEX lv_index.
    ENDLOOP.

    SORT lt_subitems BY path ASCENDING.

    LOOP AT lt_subitems ASSIGNING <ls_item>.
      AT NEW path.
        CLEAR ls_folder.
        ls_folder-path    = <ls_item>-path.
        ls_folder-sortkey = c_sortkey-dir. " Directory
        ls_folder-is_dir  = abap_true.
      ENDAT.

      ls_folder-changes = ls_folder-changes + <ls_item>-changes.

      zcl_abapgit_state=>reduce( EXPORTING iv_cur = <ls_item>-lstate
                                 CHANGING cv_prev = ls_folder-lstate ).
      zcl_abapgit_state=>reduce( EXPORTING iv_cur = <ls_item>-rstate
                                 CHANGING cv_prev = ls_folder-rstate ).

      AT END OF path.
        APPEND ls_folder TO ct_repo_items.
      ENDAT.
    ENDLOOP.

  ENDMETHOD.


  METHOD build_repo_items_offline.

    DATA: lt_tadir TYPE zif_abapgit_definitions=>ty_tadir_tt,
          ls_item  TYPE zif_abapgit_definitions=>ty_item.

    FIELD-SYMBOLS: <ls_repo_item> LIKE LINE OF rt_repo_items,
                   <ls_tadir>     LIKE LINE OF lt_tadir.


    lt_tadir = zcl_abapgit_factory=>get_tadir( )->read(
      iv_package = mo_repo->get_package( )
      io_dot     = mo_repo->get_dot_abapgit( ) ).

    LOOP AT lt_tadir ASSIGNING <ls_tadir>.
      APPEND INITIAL LINE TO rt_repo_items ASSIGNING <ls_repo_item>.
      <ls_repo_item>-obj_type = <ls_tadir>-object.
      <ls_repo_item>-obj_name = <ls_tadir>-obj_name.
      <ls_repo_item>-path     = <ls_tadir>-path.
      MOVE-CORRESPONDING <ls_repo_item> TO ls_item.
      <ls_repo_item>-inactive = boolc( zcl_abapgit_objects=>is_active( ls_item ) = abap_false ).
      IF <ls_repo_item>-inactive = abap_true.
        <ls_repo_item>-sortkey = c_sortkey-inactive.
      ELSE.
        <ls_repo_item>-sortkey  = c_sortkey-default.      " Default sort key
      ENDIF.
    ENDLOOP.

  ENDMETHOD.


  METHOD build_repo_items_online.

    DATA:
          ls_file        TYPE zif_abapgit_definitions=>ty_repo_file,
          lt_status      TYPE zif_abapgit_definitions=>ty_results_tt.

    FIELD-SYMBOLS: <ls_status>    LIKE LINE OF lt_status,
                   <ls_repo_item> LIKE LINE OF rt_repo_items.


    lt_status       = mo_repo->status( mo_log ).

    LOOP AT lt_status ASSIGNING <ls_status>.
      AT NEW obj_name. "obj_type + obj_name
        APPEND INITIAL LINE TO rt_repo_items ASSIGNING <ls_repo_item>.
        <ls_repo_item>-obj_type = <ls_status>-obj_type.
        <ls_repo_item>-obj_name = <ls_status>-obj_name.
        <ls_repo_item>-inactive = <ls_status>-inactive.
        <ls_repo_item>-sortkey  = c_sortkey-default. " Default sort key
        <ls_repo_item>-changes  = 0.
        <ls_repo_item>-path     = <ls_status>-path.
      ENDAT.

      IF <ls_status>-filename IS NOT INITIAL.
        ls_file-path       = <ls_status>-path.
        ls_file-filename   = <ls_status>-filename.
        ls_file-is_changed = boolc( <ls_status>-match = abap_false ). " TODO refactor
        ls_file-rstate     = <ls_status>-rstate.
        ls_file-lstate     = <ls_status>-lstate.
        APPEND ls_file TO <ls_repo_item>-files.

        IF <ls_status>-inactive = abap_true AND
           <ls_repo_item>-sortkey > c_sortkey-changed.
          <ls_repo_item>-sortkey = c_sortkey-inactive.
        ENDIF.

        IF ls_file-is_changed = abap_true.
          <ls_repo_item>-sortkey = c_sortkey-changed. " Changed files
          <ls_repo_item>-changes = <ls_repo_item>-changes + 1.

          zcl_abapgit_state=>reduce( EXPORTING iv_cur = ls_file-lstate
                                     CHANGING cv_prev = <ls_repo_item>-lstate ).
          zcl_abapgit_state=>reduce( EXPORTING iv_cur = ls_file-rstate
                                     CHANGING cv_prev = <ls_repo_item>-rstate ).
        ENDIF.
      ENDIF.

      AT END OF obj_name. "obj_type + obj_name
        IF <ls_repo_item>-obj_type IS INITIAL.
          <ls_repo_item>-sortkey = c_sortkey-orphan. "Virtual objects
        ENDIF.
      ENDAT.
    ENDLOOP.

  ENDMETHOD.


  METHOD constructor.
    mo_repo = io_repo.
    CREATE OBJECT mo_log.
  ENDMETHOD.


  METHOD filter_changes.

    DELETE ct_repo_items WHERE changes = 0.

  ENDMETHOD.


  METHOD get_log.
    ro_log = mo_log.
  ENDMETHOD.


  METHOD list.

    mo_log->clear( ).

    IF mo_repo->is_offline( ) = abap_true.
      rt_repo_items = build_repo_items_offline( ).
    ELSE.
      rt_repo_items = build_repo_items_online( ).
    ENDIF.

    IF iv_by_folders = abap_true.
      build_folders(
        EXPORTING iv_cur_dir    = iv_path
        CHANGING  ct_repo_items = rt_repo_items ).
    ENDIF.

    IF iv_changes_only = abap_true AND mo_repo->is_offline( ) = abap_false.
      " There are never changes for offline repositories
      filter_changes( CHANGING ct_repo_items = rt_repo_items ).
    ENDIF.

    SORT rt_repo_items BY
      sortkey ASCENDING
      obj_type ASCENDING
      obj_name ASCENDING.

  ENDMETHOD.
ENDCLASS.
