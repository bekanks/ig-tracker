# IG Tracker (kalitsiz, serversiz APK)

Ochiq (public) Instagram akkauntlarning obunachi va post sonini har kuni telefonning o'zida yozib boradi
va reyting qiladi: kim ko'p post qo'ydi, kimning obunachisi o'smoqda, kim jim turibdi.

## APK olish (telefondan)
1. github.com'da yangi repo oching (Public bo'lsa, Actions cheksiz tekin).
2. **Add file → Upload files**: shu papkadagi hamma narsani yuklang.
   `.github` papkasi ham bo'lishi shart. Telefonda papka yuklash qiyin bo'lsa, **Add file → Create new file**
   deb, nomiga `.github/workflows/build.yml` yozing va ichiga build.yml matnini qo'ying.
3. Repo → **Actions** → "Build APK" → ishga tushishini kuting (5-10 daqiqa).
4. Tugagach, o'sha run ichidan **ig-tracker-apk** (Artifacts) ni yuklab oling, zipdan `app-release.apk` ni chiqaring.
5. Telefonda o'rnating (Sozlamalarda "noma'lum manbalardan o'rnatish"ga ruxsat bering).

## Ishlatish
- `+` tugmasi: 9 ta usernameni bir yo'la kiriting (vergul yoki yangi qator bilan; havolalar ham bo'ladi).
- Ilova ochilganda 6 soatda bir marta o'zi yangilaydi; yuqoridagi tugma yoki tortib yangilash ham bor.
- Akkauntni o'chirish: ustida uzoq bosing.
- Birinchi kuni faqat joriy raqamlar ko'rinadi. Farqlar (qancha post, qancha o'sish, necha kundan beri jim) ertasidan chiqa boshlaydi.
  Har kuni kamida bir marta oching.

## Cheklovlar
- Storis ko'rinmaydi. Reels va post ajratilmaydi (jami post soni).
- Instagram rasmiy bo'lmagan bu so'rovlarni to'sishi mumkin; shunda akkaunt ostida qizil xato chiqadi, keyinroq qayta urinib ko'ring.
- Ilova yopiq paytda ishlamaydi, bildirishnoma yo'q.
