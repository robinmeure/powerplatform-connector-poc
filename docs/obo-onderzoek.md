# OBO achter APIM met Managed Identity: onderzoek en haalbaarheid

Status: onderzoek, geen code- of deploymentwijziging. Alleen primaire Microsoft Learn-bronnen. Datum: 2026-11-11.
Niet gedaan: geen live tenant-test, geen MSAL-broncode of GitHub-issues doorzocht (zie sectie 9).

## 1. Conclusie (beslissing)

| Route | Status |
|---|---|
| Delegated token **doorsturen** naar backend | Gedocumenteerd, geen OBO (en alleen toegestaan naar de bedoelde audience) |
| **Echte OBO** met client secret of certificaat (`client_assertion` ondertekend met certificaat) | **Gedocumenteerd** [B1] |
| **OBO met Managed Identity als federated credential** (UAMI-token als `client_assertion`) | **Niet expliciet gedocumenteerd voor het reguliere OBO-protocol**; samengestelde hypothese, PoC nodig |
| `authentication-managed-identity` alleen | **Geen OBO**: app-only token, gebruiker kwijt [A1] |

Haalbaarheid: OBO is technisch haalbaar. "Alleen APIM-policies, geen secret/certificaat, met MI" is **onbewezen**.
Gedocumenteerde protocolalternatieven: OBO met certificaat of secret, eventueel via een kleine tussenservice met MSAL. Ook een APIM-implementatie met `send-request` en een secret uit een Key Vault-backed named value moet nog worden gevalideerd; certificaatgebaseerde clientauthenticatie vereist een correct ondertekende JWT-clientassertion, niet alleen een TLS-clientcertificaat.
Advies: eerst PoC (sectie 8). Niet beloven dat MI+OBO werkt voordat die slaagt; een geslaagde test alleen stelt de formele support-status nog niet vast.

## 2. Het onderscheid

1. **`authentication-managed-identity`** haalt via de MI van APIM een **app-only** token op voor `resource`. De policy ondersteunt Bearer-authenticatie en tokenuitvoer via `output-token-variable-name`. Dit token heeft geen delegated gebruikerscontext: een aanwezige `oid` identificeert de service principal, niet de oorspronkelijke gebruiker. [A1]
2. **OBO** (`grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer`): een confidential client (middle-tier app) wisselt de binnengekomen gebruikerstoken (`assertion`) in voor een token voor een downstream API met delegated scopes. De gebruiker blijft behouden. [B1]
3. **MI als federated credential (FIC)** is alleen een manier om de *confidential client te authenticeren* (i.p.v. secret/cert). De app-registratie is de caller, niet de MI. [C1]

De verwachte v2-tokencontext bij OBO+MI-als-credential is `azp` = frontend-app, `oid` = oorspronkelijke gebruiker en een delegated `scp`. De backend autoriseert dan gebruiker plus middle-tier-app, niet de APIM-MI als app-only aanroeper.

```text
Power Platform -- delegated JWT (aud=frontend) + key --> APIM
APIM -- gebruiker-assertion + clientauthenticatie --> Entra OBO-tokenendpoint
APIM -- verkregen delegated JWT (aud=backend) --> backend

Onderzoeksvraag: kan APIM voor die clientauthenticatie een UAMI-token
als federated client_assertion gebruiken, in plaats van secret/certificaat?
```

**Forwarding vs OBO.** Forwarden = originele token (aud = API A/frontend) ongewijzigd doorgeven; dat is geen OBO en [B1] zegt: tokens voor de middle-tier mogen alleen naar die audience. Een header als `X-User` is geen OBO en geen cryptografisch bewijs. Een APIM subscription key is een aparte laag (toegang tot product/API) en draagt geen gebruikersidentiteit.

## 3. Bronnen (primair, Microsoft Learn)

- **A1** APIM `authentication-managed-identity`: token voor `resource`, Bearer in `Authorization`, cache tot expiry; system-assigned (default) of user-assigned via `client-id`; `output-token-variable-name`; voorbeeld "set header manually"; ook in `send-request`; token wordt as-is doorgestuurd, APIM controleert de bestemming niet; beheerders van policies kunnen tokens exfiltreren. https://learn.microsoft.com/en-us/azure/api-management/authentication-managed-identity-policy
- **B1** OBO-protocol: `assertion.aud` moet de app zijn van `client_id`; token voor andere app (bv. Graph) niet inwisselbaar; clientauth via `client_secret` of `client_assertion` ondertekend met certificaat; consent vooraf (admin consent, `knownClientApplications`, `preAuthorizedApplications`); `.default` niet combineren met andere delegated scopes; CA/MFA-fout moet als 401 + `WWW-Authenticate` claims terug naar de client. https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-on-behalf-of-flow
- **C1** App vertrouwt Managed Identity: app en MI in dezelfde tenant; **"You can only use User-Assigned Managed Identities as a credential"**; issuer `https://login.microsoftonline.com/{tenant}/v2.0`; subject = principal-ID van de MI; audience `api://AzureADTokenExchange` (USGov/China eigen waarden); max 20 FIC's; andere tenant alleen met multitenant app; andere cloud niet. https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-config-app-trust-managed-identity
- **C2** FIC-beperkingen: exact een audience, propagatievertraging (`AADSTS70021`, retry), geen wildcards, UAMI-regio Malaysia South niet, "Users can register applications"=No vereist admin. https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-considerations
- **C3** Overzicht: scenario "Azure compute + UAMI -> app" ondersteund voor toegang tot Entra-resources via client credentials. https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation
- **C4** Agent ID OBO: in de geraadpleegde bronnen gevonden voorbeeld van OBO met een MI-credential, maar voor *agent identity blueprints* (`fmi_path`, tweestaps T1 met `scope=api://AzureADTokenExchange/.default`). Ander model; niet automatisch geldig voor gewone apps. https://learn.microsoft.com/en-us/entra/agent-id/agent-on-behalf-of-oauth-flow
- **P1** Custom connector OAuth 2.0: client id + secret, "client credentials grant type is not supported", token via `Authorization`. https://learn.microsoft.com/en-us/connectors/custom-connectors/connection-parameters
- **M1** MSAL.NET OBO: `AcquireTokenOnBehalfOf` zoekt zelf in de cache, slaat geen refresh tokens op; CA/MFA geeft `MsalUiRequiredException` met `Claims`, door te geven als 401 + `WWW-Authenticate`. https://learn.microsoft.com/en-us/entra/msal/dotnet/acquiring-tokens/web-apps-apis/on-behalf-of-flow
- **L1** Claims challenges. https://learn.microsoft.com/en-us/entra/identity-platform/claims-challenge

## 4. Specifieke vragen

| Vraag | Antwoord | Status |
|---|---|---|
| MI-federation als clientauth voor OBO? | [B1] noemt secret en certificaat-assertion; [C1]/[C3] beschrijven FIC voor client credentials. In de geraadpleegde bronnen is OBO+MI-FIC voor een gewone app niet expliciet bevestigd. Agent ID [C4] gebruikt een ander model. | **Niet bevestigd; niet hetzelfde als uitgesloten** |
| `api://AzureADTokenExchange` | Vereist als audience van het MI-token dat als FIC-assertion dient [C1][C2]. In APIM `resource="api://AzureADTokenExchange"` is aannemelijk (vrije string) maar niet in de policydoc genoemd. | Samengesteld |
| Single-tenant app/FIC | MI en app in dezelfde tenant [C1]; single-tenant volstaat. | Gedocumenteerd |
| User- vs system-assigned | Als FIC-credential **alleen user-assigned** [C1]. De APIM-policy ondersteunt beide [A1]. | Gedocumenteerd |
| Tenantbeperkingen | Admin nodig bij "register applications"=No; Azure Policy kan FIC blokkeren; geen cross-cloud; propagatievertraging [C1][C2]. | Gedocumenteerd |
| Assertion-audience | `assertion.aud` = client_id van de OBO-app (frontend) [B1]; het FIC-token is een apart MI-token (aud `api://AzureADTokenExchange`). | Gedocumenteerd |
| Backend scopes/consent | Backend heeft delegated scope nodig; frontend krijgt die permission en passend consent. `knownClientApplications` kan gecombineerde consent ondersteunen, maar is niet zelf een verleende toestemming [B1]. | Gedocumenteerd |

## 5. Kan APIM dit zonder tussenservice?

**R1 (gedocumenteerd, geen OBO).** `authentication-managed-identity` voor app-only; geen gebruiker.

**R2 (OBO met secret/certificaat; protocol gedocumenteerd [B1], APIM-uitwerking samengesteld).** Sla het binnenkomende token op in een variabele, `send-request` POST naar `https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token` met jwt-bearer, `client_id`=frontend, `scope`=backend-scope, `assertion`=gebruikerstoken en `client_secret` uit Key Vault named value. `send-request` is gedocumenteerd [A1]; een volledige OBO-policy is geen officieel voorbeeld in de gelezen bronnen. Certificaat-assertion bouwen in policy-expressies is lastig; secret is simpeler maar vergt secretbeheer.

**R3 (hypothese, MI-FIC).**
1. `authentication-managed-identity resource="api://AzureADTokenExchange" client-id="<UAMI>" output-token-variable-name="fic"` (variabele-uitvoer gedocumenteerd [A1]; resource-waarde is aanname; of de policy ook `Authorization` overschrijft is onduidelijk, dus eerst de gebruikerstoken in een variabele bewaren).
2. `send-request` OBO met `client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer`, `client_assertion=fic`, `assertion=<gebruikerstoken>`, `scope=api://backend/<scope>`, `requested_token_use=on_behalf_of`.
3. Resultaat in `Authorization` zetten.
Onbewezen: of Entra de MI-FIC-assertion in deze OBO-aanroep accepteert. Test dit met correcte audience, tenant, consent en FIC-configuratie. Een fout kan ook configuratie of propagatie betreffen en bewijst niet direct dat de combinatie onmogelijk is.

**R4 (tussenservice).** Kleine service met MSAL (`AcquireTokenOnBehalfOf`); regelt cache en claims [M1]. Ook hier is MI-FIC-OBO niet bevestigd; certificaat is de zekerste credential.

Er is in de geraadpleegde bronnen geen officieel gedocumenteerde "APIM-policy-only OBO met MI".

## 6. Caching, claims/CA, headers

- **Caching.** `authentication-managed-identity` cachet het MI-token [A1]; dat is geen cache voor het delegated OBO-resultaat. Begin de PoC zonder eigen OBO-cache. Gebruik later bij voorkeur de ondersteunde MSAL-cache [M1]. Een eigen APIM-cache vereist aparte validatie van scheiding op inkomende assertion, tenant, client, downstream-resource/scopes en claims-context, met begrensde vervaltijd. Alleen gebruiker en scopes zijn geen voldoende bewezen sleutel. Dit is ontwerpadvies, geen uitgewerkt cacheontwerp.
- **CA/claims.** Als OBO aanvullende gebruikersinteractie vereist, geef de claims challenge terug volgens [B1][M1][L1], doorgaans als 401 + `WWW-Authenticate`. Niet iedere tokenfout is een claims challenge. Of de gekozen Power Platform-client dit omzet naar passende interactieve aanmelding is **niet bevestigd**; test dit afzonderlijk.
- **Headers/subscription key.** Headers zijn geen OBO of vertrouwensbasis. Subscription key blijft een aparte productgate en wordt niet naar de backend doorgestuurd.
- **Beveiliging.** Wie policies kan wijzigen kan MI-tokens exfiltreren [A1]; beperk beheerrechten, gebruik een dedicated UAMI.

## 7. Impact op deze repo (door parent geverifieerde feiten)

Bronnen: [infra/main.bicep](../infra/main.bicep) (r.14-25), [infra/policies/api.xml](../infra/policies/api.xml) (r.4-19), [scripts/Initialize-Entra.ps1](../scripts/Initialize-Entra.ps1) (r.36-90), [src/Backend/BackendAuthorization.cs](../src/Backend/BackendAuthorization.cs) (r.7-22), [src/Backend/Program.cs](../src/Backend/Program.cs), [tests/Backend.Tests/BackendAuthorizationTests.cs](../tests/Backend.Tests/BackendAuthorizationTests.cs), [connector/auth-overlay.json](../connector/auth-overlay.json).

- **`/proof` is scenario 1 (app-only).** APIM valideert het delegated JWT (tenant, audience frontend, connector-client, `Demo.Read`; api.xml r.4-17), vervangt `Authorization` door een MI-token (r.18) en verwijdert de subscription key (r.19). De backend eist `idtyp=app`, `roles=Demo.Invoke`, exacte `oid` en `azp` van de APIM-MI en verwerpt `scp`/`upn`/`preferred_username`/`unique_name`/`email`; de test borgt die weigering. OBO-output wordt dus **bewust geweigerd**; `/proof` niet versoepelen.
- **Entra-setup past niet bij OBO.** Frontend/API A heeft delegated `Demo.Read` (Initialize-Entra r.36-51); backend/API B heeft alleen app role `Demo.Invoke`, geen delegated scope (r.53-68); connector-client heeft delegated frontend-scope + tenant-wide consent (r.70-90). Voor OBO nodig: delegated scope op backend, frontend als confidential client met die permission + consent, en een frontend-credential (cert/secret, of UAMI-FIC voor R3).
- **System-assigned MI blokkeert R3.** main.bicep r.14-25 maakt APIM met SystemAssigned; FIC-credential vereist user-assigned [C1]. Toevoegen: UAMI op APIM (`client-id` in policy) en FIC op de frontend-app. De system-assigned MI blijft voor `/proof`.
- **Voorstel.** Aparte route `/proof-obo` met eigen policy en eigen backend-autorisatie (vereist `scp`, `azp`=frontend, `oid`=gebruiker, audience backend; weigert `idtyp=app`), plus de noodzakelijke gebruikers- en resourceautorisatie. `auth-overlay.json` (resource = frontend) past bij `assertion.aud` [B1]; voeg een connectoroperatie toe voor de nieuwe route. De bestaande connectorfederation blijft losstaan van de nieuwe credential voor de frontend/OBO-app. Een extra OAuth-clientsecret op de connector is hiervoor niet vereist.

## 8. PoC-acceptatiecriteria

1. Connector-token (aud=frontend, `scp=Demo.Read`) wordt door APIM gevalideerd; zonder geldig token 401.
2. R2: backend ontvangt token met `scp`, `oid`=gebruiker, `azp`=frontend, aud=backend; andere gebruiker geeft andere `oid`.
3. R3: UAMI op APIM + FIC op frontend (issuer/subject/audience volgens [C1]); OBO via `send-request` slaagt zonder secret/certificaat. Bij falen alleen geredigeerde foutcodes vastleggen, configuratie/consent/propagatie uitsluiten en zo nodig Microsoft-support raadplegen. Tokens nooit loggen.
4. `/proof-obo` weigert `idtyp=app`, ontbrekende `scp`, verkeerde `azp`/audience; `/proof` blijft app-only en ongewijzigd.
5. Het frontend-audience-token bereikt de backend nooit; de assertion gaat alleen naar het tokenendpoint.
6. Eerst zonder eigen OBO-cache: twee gebruikers krijgen hun eigen backendidentiteit. Als later caching wordt toegevoegd: test ook scheiding van assertions/claims-context, expiry, fouten en verschillende downstream-scopes.
7. CA/MFA-scenario: OBO-fout levert 401 + `WWW-Authenticate` met `claims`; noteer het Power Platform-gedrag zonder aanname.
8. Subscription key wordt apart gevalideerd en niet doorgestuurd; geen secrets in logs of policy-tekst.

## 9. Onzekerheden en support-status

- **Niet bevestigd:** OBO met MI-FIC voor een gewone app-registratie (alleen het Agent ID-model [C4]). Support-status onbekend; niet afleiden uit client-credentials-docs.
- **Niet geverifieerd:** `resource="api://AzureADTokenExchange"` in `authentication-managed-identity`; combinatie `output-token-variable-name` met de `Authorization`-header; APIM-cachepolicydocs; MSAL-broncode en GitHub-issues (niet geraadpleegd).
- **Niet gedocumenteerd:** Power Platform-gedrag bij claims challenge; geen propagatiebelofte.
- **Aanbeveling:** R3 gericht onderzoeken als secretless voorkeursrichting. R2 of een MSAL-tussenservice zijn alternatieven met gedocumenteerde protocolbouwstenen, maar ook hun concrete implementatie vereist validatie. Geen van deze routes is in deze repo productiebewezen.