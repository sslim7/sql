
  ┌──────┬──────────┬───────────────┬───────────────────┐
  │ NO   │ deviceOs │ deviceAppType │       app         │
  ├──────┼──────────┼───────────────┼───────────────────┤
  │ 1    │ DVOS_002 │ APPT_012      │ tableorderAndroid │
  ├──────┼──────────┼───────────────┼───────────────────┤
  │ 2    │ DVOS_002 │ APPT_016      │ homeLauncher      │
  ├──────┼──────────┼───────────────┼───────────────────┤
  │ 3    │ DVOS_001 │ APPT_001      │ agent             │
  ├──────┼──────────┼───────────────┼───────────────────┤
  │ 4    │ DVOS_001 │ APPT_014      │ daemon            │
  ├──────┼──────────┼───────────────┼───────────────────┤
  │ 5    │ DVOS_001 │ APPT_015      │ monkiClicker      │
  ├──────┼──────────┼───────────────┼───────────────────┤
  │ 6    │ DVOS_001 │ APPT_012      │ kdsWindows        │
  ├──────┼──────────┼───────────────┼───────────────────┤
  │ 7    │ DVOS_002 │ WAITING_CEO   │ waitingCeo        │
  ├──────┼──────────┼───────────────┼───────────────────┤
  │ 8    │ DVOS_002 │ WAITLIST      │ waitlist          │
  └──────┴──────────┴───────────────┴───────────────────┘

SELECT device_os, device_app_type, app_version, file_url
  FROM pos.tb_app_version
  WHERE (device_os, device_app_type) IN (
    ('DVOS_002', 'APPT_012'),
    ('DVOS_002', 'APPT_016'),
    ('DVOS_001', 'APPT_001'),
    ('DVOS_001', 'APPT_014'),
    ('DVOS_001', 'APPT_015'),
    ('DVOS_001', 'APPT_012'),
    ('DVOS_002', 'WAITING_CEO'),
    ('DVOS_002', 'WAITLIST')
  )
  ORDER BY device_os, device_app_type;

select * from pos.tb_app_version;
