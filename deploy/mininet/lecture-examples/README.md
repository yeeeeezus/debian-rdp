# ملفات التدريب العملي — Mininet و SDN (جاهزة في هذا النظام)

كل الأمثلة تعمل داخل بيئة المعمل المعزولة (بدون sudo). الفرق الوحيد عن
المحاضرة: لا يوجد موديل OVS في النواة، لذا يقوم طبق التوافق
(lecture_compat.py) تلقائياً بـ:
- OVSSwitch → جسر Linux (LxBr) مع تعلم L2
- RemoteController → يعمل، و ryu-manager متاح فعلياً ويستمع على 6653
- حلقات الشبكة (ring) → "loop-guard" يسدّ وصلة احتياطية (نفس فكرة STP)

## التشغيل
1. افتح طرفية "Mininet SDN Lab" من سطح المكتب (أو `mininet-lab`)
2. شغّل المتحكم في طرفية مستقلة داخل المعمل:
   `ryu-manager ryu.app.simple_switch_13`
3. شغّل المثال: `cd ~/mininet-labs && python3 example01.py`
4. داخل واجهة `mininet>` جرّب: `help`, `nodes`, `net`, `links`, `pingall`, `iperf`, `py h1.IP()`
5. للخروج: `exit`

## الملفات
| الملف | الطوبولوجيا / الهدف |
|---|---|
| example01.py | أول شبكة: مبدل واحد + مضيفان |
| example02.py | نجمية: 4 مضيفين على مبدل واحد |
| example03.py | خطية: 3 مبدلات سلسلة |
| example04.py | شجرية (Tuples) |
| example05.py | صنف Topo مخصص (count, per_switch) |
| example06.py | حلقية Ring مع وصلة احتياطية (loop-guard = دور STP) |
| example09.py | معلمة بخيارات سطر الأوامر --switches/--hosts |
| example13.py | فشل الوصلات واستعادتها برمجياً |
| 01_delay_display.py | قياس RTT (min/avg/max) بين h1 و h4 |
| 03_throughput_display.py | قياس الإنتاجية بـ iperf3 (Mbps) |
