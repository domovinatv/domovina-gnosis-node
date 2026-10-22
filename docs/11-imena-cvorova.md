# 11 — Imena čvorova i katalog po županijama

> Odluka: [ADR-012](02-decisions.md#adr-012). Katalog je plan razvoja mreže čvorova za sljedeće mjesece i godine.
> Istraživanje 2026-10-22 (web, izvori uz svaki redak u [istraživanju](research/2026-10-22-katalog-svetaca-po-zupanijama.md)). Statusi Carla Acutisa, Pier Giorgia Frassatija, Ivana Kapistrana i Kvirina provjereni su i preko Magisterium AI.

## Vizija

Barem **21 čvor, po jedan u svakoj županiji i Gradu Zagrebu**. Ime čvora je ime sveca ili blaženika vezanog uz županiju u kojoj čvor stoji: rođenje, djelovanje, smrt, grob, relikvije ili zaštitništvo grada ili biskupije.

## Pravila imenovanja

1. **Ime iz kataloga je vezano uz lokaciju.** Novi čvor u županiji dobiva prvo slobodno ime s njezinog popisa (redoslijed = prioritet).
2. **Selidba čvora mijenja ime.** Kad čvor preseli u drugu županiju, dobiva prvo slobodno ime nove županije. Tunel (UUID) ostaje isti, mijenjaju se samo `NODE_NAME`, DNS rute i ingress ([postupak](#selidba)).
3. **Simbolična imena** (izvan kataloga) vezana su uz čvor, ne uz lokaciju, i ne mijenjaju se selidbom. Prvi čvor je `acutis`.
4. **Ime se ne koristi ponovno.** Ime ugašenog ili preseljenog čvora ostaje potrošeno. Sljedeći čvor u toj županiji uzima sljedeće ime s popisa, kako stari URL-ovi i tokeni u Workerima ne bi tiho počeli pogađati drugi stroj.
5. **Hostname:** `<ime>-rpc.mpt.hr` (HTTP) i `<ime>-ws.mpt.hr` (WebSocket). Ime je malim slovima, ASCII, bez dijakritika. Oblik `rpc.<ime>.mpt.hr` traži plaćeni Advanced Certificate jer Universal SSL pokriva samo `*.mpt.hr`.
6. **U hostnameu nema lokacije ni IP-a.** Lokacija je u tablici [Čvorovi](#cvorovi); ulica nije u repou jer je repo javan.
7. Prednost imaju **sveci i blaženici**. Sluge Božji (SB) su rezerva i označeni su.

## Čvorovi {#cvorovi}

| Ime | Hostnameovi | Županija | Mjesto | Stroj | Javni IP | Od |
| --- | --- | --- | --- | --- | --- | --- |
| `acutis` (simbolično) | `acutis-rpc.mpt.hr`, `acutis-ws.mpt.hr` | Zagrebačka | Donja Lomnica (Velika Gorica) | MacBook Pro 16" i9, 64 GB | 89.201.137.96 ([docs/10](10-network.md)) | 2026-10-11 (sync), tunel 2026-10-22 |

## Katalog po županijama

Prvo ime u stupcu „Prioritet” je plan; ostala su rezerva za drugi čvor u istoj županiji ili ako se prvo ime ne prihvati.

| # | Županija | Prioritet (slug) | Veza |
| --- | --- | --- | --- |
| 1 | Grad Zagreb | 1. `merz` — bl. Ivan Merz (2003) | profesor u Zagrebu, umro u Zagrebu 1928. |
| | | 2. `kazotic` — bl. Augustin Kažotić | zagrebački biskup 1303.–1322., relikvijar u riznici katedrale |
| | | 3. `ladislav` — sv. Ladislav | osnovao Zagrebačku biskupiju oko 1094. (neprovjereno) |
| 2 | Zagrebačka | 1. `stepinac` — bl. Alojzije Stepinac (1998) | rođen u Brezariću kraj Krašića, umro u Krašiću 1960. |
| | | 2. `kuharic` — SB Franjo Kuharić | rođen u Gornjem Pribiću (dolina Krašića) |
| | | 3. `lang` — Josip Lang | rođen u Lepšiću kraj Ivanić-Grada; status kauze neprovjeren |
| 3 | Krapinsko-zagorska | 1. `ivanpavao` — sv. Ivan Pavao II. (2014) | u Mariji Bistrici 1998. proglasio Stepinca blaženim (posjet, ne život) |
| 4 | Sisačko-moslavačka | 1. `kvirin` — sv. Kvirin Sisački | biskup Siscije, mučenik oko 309., zaštitnik Siska i biskupije |
| | | 2. `pavletic` — SB fra Ivan Bonifacije Pavletić | rođen u Zbjegovači, kršten u Kutini |
| 5 | Karlovačka | 1. `josip` — sv. Josip | zaštitnik Karlovca, Nacionalno svetište sv. Josipa na Dubovcu |
| 6 | Varaždinska | 1. `nikola` — sv. Nikola | zaštitnik Varaždina (Dan Grada 6. 12.) |
| 7 | Koprivničko-križevačka | 1. `krizevcanin` — sv. Marko Križevčanin (1995) | rođen u Križevcima 1589., zaštitnik Bjelovarsko-križevačke biskupije |
| 8 | Bjelovarsko-bilogorska | 1. `bernadeta` — bl. Bernadeta Banja (2011), Drinska mučenica | rođena u Velikom Grđevcu |
| 9 | Primorsko-goranska | 1. `vid` — sv. Vid | zaštitnik Rijeke (Statut Grada), katedrala sv. Vida |
| | | 2. `marin` — sv. Marin | po predaji rođen u Loparu na Rabu, osnivač San Marina |
| 10 | Ličko-senjska | 1. `juraj` — sv. Juraj | zaštitnik Senja |
| | | 2. `magdalena` — sv. Marija Magdalena | zaštitnica Gospića |
| | | 3. `jakov` — sv. Jakov apostol | zaštitnik nekadašnje Krbavske biskupije (Udbina) |
| 11 | Virovitičko-podravska | 1. `roko` — sv. Roko | zaštitnik Virovitice |
| 12 | Požeško-slavonska | 1. `terezija` — sv. Terezija Avilska | zaštitnica Požege i katedrale |
| | | 2. `lovro` — sv. Lovro | zaštitnik Požeške biskupije |
| 13 | Brodsko-posavska | 1. `jula` — bl. Marija Jula Ivanišević (2011), Drinska mučenica | rođena u Godinjaku (Staro Petrovo Selo) |
| | | 2. `nepomuk` — sv. Ivan Nepomuk | zaštitnik Slavonskog Broda (Dan Grada 16. 5.) |
| 14 | Zadarska | 1. `krsevan` — sv. Krševan | glavni zaštitnik Zadra (grb, zastava, Dan Grada 24. 11.) |
| | | 2. `stosija` — sv. Stošija (Anastazija) | relikvije i katedrala u Zadru |
| | | 3. `simun` — sv. Šimun Bogoprimac | tijelo u crkvi sv. Šimuna u Zadru |
| | | 4. `jakovzadranin` — bl. Jakov Zadranin | rođen u Zadru oko 1400. |
| 15 | Osječko-baranjska | 1. `petar` — sv. Petar apostol | sv. Petar i Pavao su zaštitnici Osijeka (Statut Grada), konkatedrala u Osijeku |
| 16 | Šibensko-kninska | 1. `tavelic` — sv. Nikola Tavelić (1970) | rođen u Šibeniku, prvi kanonizirani Hrvat |
| | | 2. `mihovil` — sv. Mihovil arkanđeo | zaštitnik Šibenika i biskupije |
| | | 3. `antic` — SB fra Ante Antić | rođen na Prviću (neprovjereno) |
| 17 | Vukovarsko-srijemska | 1. `kapistran` — sv. Ivan Kapistran | umro u Iloku 1456. |
| | | 2. `polion` — sv. Euzebije i Polion | mučenici Cibalae (Vinkovci) |
| | | 3. `burik` — SB Ivan Burik | župnik u Tovarniku, ubijen 1991. |
| 18 | Splitsko-dalmatinska | 1. `dujam` — sv. Dujam | salonitanski biskup, zaštitnik Splita, relikvije u katedrali |
| | | 2. `kazotic` — bl. Augustin Kažotić | rođen u Trogiru (dijeli se s Gradom Zagrebom: tko prvi) |
| | | 3. `trogirski` — sv. Ivan Trogirski | trogirski biskup i zaštitnik Trogira |
| 19 | Istarska | 1. `bulesic` — bl. Miroslav Bulešić (2013) | rođen u Čabrunićima, mučenik u Lanišću 1947., beatificiran u Puli |
| | | 2. `mauro` — sv. Mauro Porečki | prvi porečki biskup, relikvije u Eufrazijevoj baziliki |
| | | 3. `eufemija` — sv. Eufemija | relikvije i zaštitništvo u Rovinju |
| | | 4. `bonifacio` — bl. Franjo Bonifacio (2008) | svećenik u Krasici kraj Grožnjana, ubijen 1946. |
| 20 | Dubrovačko-neretvanska | 1. `petkovic` — bl. Marija Propetog Isusa Petković (2003) | rođena u Blatu na Korčuli |
| | | 2. `vlaho` — sv. Vlaho | zaštitnik Dubrovnika, relikvije u katedrali |
| | | 3. `gabric` — SB Ante Gabrić | rođen u Metkoviću, misionar u Bengalu |
| 21 | Međimurska | 1. `jeronim` — sv. Jeronim | stara predaja da je Štrigova antički Stridon (znanstveno sporno) |

**Slabe točke kataloga:**
- **Osječko-baranjska i Međimurska** nemaju sveca ili blaženika s osobnom vezom; imena su zaštitnik grada (`petar`) i sporna predaja (`jeronim`). Kandidati se traže kad se zna mjesto čvora (mjesna župa).
- **Krapinsko-zagorska** (`ivanpavao`) ima samo vezu jednog posjeta.
- **Karlovačka, Varaždinska, Koprivničko-križevačka, Bjelovarsko-bilogorska, Virovitičko-podravska i Osječko-baranjska** imaju samo jedno ime. Drugi čvor u tim županijama treba novo istraživanje.

## Simbolična imena (vezana uz čvor)

| Ime | Svetac | Status |
| --- | --- | --- |
| `acutis` | sv. Carlo Acutis, zaštitnik interneta i programera (kanoniziran 7. 9. 2025.) | **zauzeto: i9** |
| `frassati` | sv. Pier Giorgio Frassati (kanoniziran 7. 9. 2025.) | slobodno |
| `mandic` | sv. Leopold Bogdan Mandić (1983.), rođen u Herceg Novom | slobodno |
| `bosco` | sv. Ivan Bosco, zaštitnik mladih | slobodno |
| `cirilmetod` | sv. Ćiril i Metod, glagoljaška baština | slobodno |

## Selidba čvora {#selidba}

Primjer: čvor `kvirin` seli iz Siska u Karlovac i postaje `josip`.

1. Novo ime iz kataloga upisati u tablicu [Čvorovi](#cvorovi) (stari redak ostaje s datumom do kada je vrijedio).
2. `tunnel route dns <tunnel> josip-rpc.mpt.hr` i `josip-ws.mpt.hr` (treba `cert.pem`, [docs/06](06-rpc-exposure.md#postavljanje-na-macu)).
3. Workere prebaciti na nove hostnameove, pa `NODE_NAME=josip` u `config/node.env` i `sudo scripts/30-services.sh install tunnel`. Ingress tada poznaje samo novo ime, a stari hostnameovi vraćaju 404.
4. Access aplikaciji dodati nove hostnameove, stare maknuti; u Cloudflare DNS obrisati stare CNAME zapise.
5. Ako na čvoru radi validator: selidba stroja nije selidba ključeva, ali vrijedi [docs/08 § 5](08-validator.md#5-selidba-na-drugi-stroj-ili-reinstalacija) ako se mijenja stroj.

## Vezani dokumenti

- [ADR-011](02-decisions.md#adr-011) (tunel po čvoru), [ADR-012](02-decisions.md#adr-012) (imena)
- [docs/06 — RPC prema van](06-rpc-exposure.md)
- [docs/10 — Mreža i port forwarding](10-network.md)
