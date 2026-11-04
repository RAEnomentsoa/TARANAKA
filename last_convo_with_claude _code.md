Written for: the mobile developer and your partner (endpoint.md, in French).

All the endpoints are built and nothing is committed. check reports no issues and all 174 tests pass: your 35 plus 139 new ones, including everything on your list. I changed one old test, because /me now also returns csb_id. Migration 0004 is applied, and your real database still has no users, children or audit lines.

Result
Your danger-sign change: an ASC's sign without csb_id is saved with "avertissement": "Référencement non créé : CSB manquant" and appears in danger_sans_referencement. An unknown csb_id is also saved, with the warning "CSB inconnu".
danger_sans_referencement: it also shows a pregnancy whose new sign came after an older referral, so that sign isn't hidden by the old one.
Swagger: /api/schema/ and /api/docs/ answer 200 and the schema validates with no warnings. The doc examples come from real API responses captured on the test database, with a few names and ids adjusted. I haven't opened the Swagger page in a browser.
Not tested
Simultaneous requests: the row locks and the retry when two phones get the same code at once have never run with truly concurrent requests. The retry itself is only tested with a simulated clash.
A real server or phone: the tests use Django's test client and skip the JWT login on the new endpoints.
/admin/: the new csb field in the forms hasn't been opened. The rule behind it is tested.
Files
Area	Files
Migration	comptes/migrations/0004_utilisateur_csb.py
Shared code (new)	synchro/: services.py, serializers.py, exceptions.py, filters.py, pagination.py, outils_tests.py
Endpoints (new)	serializers.py, filters.py, urls.py in nutrition, referencement, referentiel, sante_femme, plus services.py in all but referentiel; comptes/api_urls.py
Changed code	views.py and tests.py in those 4 apps and comptes; synchro/views.py, synchro/models.py; comptes/: models.py, serializers.py, services.py, permissions.py, admin.py; config/settings.py, config/urls.py; requirements.txt
Docs	endpoint.md, regles_validation.md, taranaka_tables_serveur.md
Changes to your table file (items 25–28):

utilisateur gains csb_id.
journal_audit.action also records status_change.
A soft delete now also saves device_id.
The code example now uses the new format.
Decisions for you
Are these danger-sign refusals OK? A missing or unknown type_danger_grossesse_id still returns 400, because the column can't be empty. An unreadable date also returns 400; a missing date uses the current time. I recommend keeping the type refusal, since the phone preloads those types, and using the current time for an unreadable date too, so a bad date never loses a sign.
Which time zone should the codes use? TIME_ZONE is UTC, so a referral created before 03:00 in Madagascar gets the previous day in its MMDD. I recommend Indian/Antananarivo, though it also changes how Django displays times in /admin/.
Who provides the lookup data? Provinces, regions, CSB and danger types are empty, so you can't create a child or a danger sign until they're filled. I can write a data migration or an import command if you have the lists.
Should /profiles/ have a search? You didn't ask for filters there, so an ASC choosing mere has to page through their region's women, 50 at a time. I recommend adding search; it's a small change.
Who resets a forgotten PIN? The API can't do it: /profiles/ doesn't change PINs and changer-pin needs the old one. Only /admin/ can for now, so I recommend an admin-only reset action in the next step.
Other behaviour to check
Admin danger signs: an admin's sign creates no referral, because you said ASC only.
Other child records: soft-deleting a child doesn't touch journal_alimentaire or consultation_nutritionnelle, which have no endpoints yet. Those future endpoints must filter out deleted children.