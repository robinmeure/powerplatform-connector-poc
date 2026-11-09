# Delegated of app-only: keuze voor Power Platform en APIM

Dit document vat de architectuurkeuze, het centrale beheer en de app-only
alternatieven samen en beantwoordt de oorspronkelijke vragen per processtap in
hoofdstuk 4. De huidige repo bewijst de delegated route; de app-only alternatieven
hieronder zijn ontwerpopties en zijn niet in deze PoC gerealiseerd.

## 1. Kern: onderscheid de twee verbindingen

```text
Huidige repo:
Power Platform Custom Connector
  -> delegated gebruikerstoken + APIM subscription key
APIM
  -> app-only token van APIM Managed Identity
Backend
```

De backend wordt dus al app-only aangeroepen. Alleen de verbinding van Power
Platform naar APIM gebruikt nog een gebruikersidentiteit.

- **Delegated:** de applicatie handelt namens een gebruiker. Autorisatie moet de
  toegestane client, gedelegeerde scopes en waar nodig gebruikersrechten controleren.
- **App-only:** de applicatie handelt als zichzelf, zonder gebruiker. Autorisatie
  gebruikt de toegestane applicatie-identiteit en applicatierollen.
- **Subscription key:** toegang tot een APIM Product, quota en gebruiksregistratie.
  Een key is geen Entra-token en vervangt JWT-autorisatie niet.

**Belangrijk:** ingebouwde OAuth van generieke Custom Connectors ondersteunt geen
`client_credentials`. De connectoroptie **Managed identity** vervangt het
OAuth-clientsecret via federation, maar blijft gedelegeerde gebruikersauthenticatie.
Een Service Principal als flow-eigenaar verandert dit niet.

Bronnen: [authenticatiemethoden][auth] en [connector Managed identity][connector-mi].

## 2. Wanneer en waarom delegated gebruiken?

Kies de aanpak van deze repo wanneer:

- De API-aanroep namens een gebruiker mag of moet plaatsvinden.
- Een Custom Connector voor hergebruik in Power Platform gewenst is.
- Een eerste interactieve aanmelding en eventueel later herstel van de Connection
  acceptabel zijn.
- INET een afzonderlijke Power Platform-route accepteert die delegated tokens
  autoriseert en vervolgens APIM als backendidentiteit gebruikt.
- Geen extra Function, Logic App of andere tussenservice gewenst is.

### Inrichting en beveiligingsgrens

1. De gebruiker maakt een lokale OAuth-Connection met een subscription key.
2. De connector stuurt beide naar APIM.
3. APIM valideert de subscription key, tenant, audience, toegestane connectorclient
   en benodigde scope; aanvullende gebruikersautorisatie is afhankelijk van de API.
4. Pas na succesvolle autorisatie verkrijgt APIM een backendtoken met zijn
   Managed Identity en vervangt het de Authorization-header.
5. De backend controleert APIM-identiteit en applicatierol.

Dit is **niet** ongewijzigd aansluiten op een uitsluitend app-only APIM-ingang.
Die ingang vereist een andere tokencontext. Maak voor delegated een expliciete
route/policy, zonder bestaande controles voor andere consumers af te zwakken.

De backend ziet APIM, niet de oorspronkelijke gebruiker. APIM moet daarom de
oorspronkelijke aanroeper afdoende autoriseren en relevante auditcorrelatie behouden.

### Managed Identity betekent hier twee verschillende dingen

| Plaats | Betekenis | Gebruikersvrij? |
|---|---|---|
| Custom Connector | Federation vervangt het OAuth-clientsecret | Nee |
| APIM naar backend | APIM vraagt als applicatie een backendtoken aan | Ja |

Connectorfederation vereist een single-tenant clientappregistratie, een concrete
tenant-GUID en registratie van issuer, subject en OAuth-redirect. Een andere
Power Platform-omgeving krijgt een eigen connectoridentiteit.

### Wat bewijst de repo?

Volgens de vastgelegde live resultaten slaagde een managed flow voor en na een
compatibele connectorupdate met dezelfde Connection en Connection Reference,
zonder herauthenticatie tussen die runs.

Dit vereiste gecontroleerde correcties aan policies, solution layers en
doelomgevingsfederation. Het bewijst geen onbeperkt geldige Connection, volledig
unattended initiatie of automatisch veilige managed import.

Zie [implementatiesamenvatting](implementation-summary.md),
[architectuur](architecture.md) en [deploymentprocedure](deployment.md).

## 3. Wanneer app-only gebruiken?

Kies app-only wanneer:

- Een proces zelfstandig draait, zonder afhankelijkheid van een gebruikersaccount.
- API-rechten aan een toepassing moeten worden toegekend, niet aan een gebruiker.
- Achtergrondverwerking en continuiteit bij personeelswisselingen centraal staan.
- INET een app-only JWT bij binnenkomst in APIM verplicht stelt.

App-only lost niet automatisch provisioning, credentialbeheer of autorisatie op.
De uitvoerende component moet een ondersteunde manier hebben om als applicatie
een token te verkrijgen. De huidige generieke Custom Connector biedt dat niet
via ingebouwde OAuth.

### Beschikbare routes

| Route | Gebruikersvrij bij runtime | App-only JWT bij INET APIM | Custom Connector |
|---|---|---|---|
| A. API-key-connector naar APIM, daarna APIM Managed Identity | Ja | Nee, eerste verbinding gebruikt een key | Behouden |
| B. Power Automate HTTP-aanroep met Service Principal | Ja | Ja | Vervangen voor deze aanroep |
| C. Connector naar beveiligde adapter, daarna Managed Identity naar INET APIM | Alleen bij gebruikersvrije adapterauthenticatie | Ja, vanuit adapter | Behouden |

### A. Geen tussenservice, maar gewijzigde beveiligingsafspraak

Maak een afzonderlijke API-key-connector en APIM-route. Laat APIM het abonnement
en de toegestane operaties autoriseren en behoud de bestaande APIM Managed Identity
naar de backend.

Dit verwijdert gebruikers-OAuth, maar voldoet **niet** aan de eis
"subscription key plus app-only JWT op de verbinding naar APIM".
Kies dit alleen na expliciete instemming van INET/security. Richt abonnementen,
rotatie, intrekking en quota per passende toepassing-/omgevingsgrens in.

### B. Echte app-only ingang zonder extra compute

Gebruik voor achtergrondflows een HTTP-aanroep met applicatieauthenticatie,
in plaats van de Custom Connector-aanroep.

Benodigd:

1. Een Entra-appregistratie met passende scheiding tussen toepassingen en OTAP.
2. Toegekende applicatierollen/application permissions voor de APIM-facing API.
3. Centraal beveiligde applicatiecredentials en subscription keys, inclusief rotatie.
4. Een flow die via `client_credentials` een token verkrijgt en beide meestuurt.
5. Een APIM-policy voor app-only tokens, los van de bestaande delegated scopecheck.
6. Beperkte bewerkrechten en beveiligde inputs/outputs om credentiallekken te voorkomen.

Verwar de HTTP-aanroep niet met de connector **HTTP with Microsoft Entra ID**;
app-only ondersteuning moet voor de gekozen actie en authenticatie worden
vastgesteld. Deze route vereist nog een gerichte PoC in de doelomgeving.

De backend kan APIM Managed Identity blijven vertrouwen. Als het oorspronkelijke
Service Principal-token wordt doorgestuurd, moet ook de backendautorisatie worden
aangepast: deze repo accepteert uitsluitend de vastgelegde APIM-identiteit.

### C. Custom Connector en bestaande INET-ingang behouden

Voeg een beveiligde adapter toe, bijvoorbeeld een Azure Function:

```text
Custom Connector
  -> beveiligde, gebruikersvrije verbinding
Adapter
  -> Managed Identity JWT + subscription key
INET APIM
  -> backend
```

Geef de adapteridentiteit de benodigde applicatierollen en beheer de subscription
key centraal. Ontwerp de eerste verbinding afzonderlijk, bijvoorbeeld met een
API-key-Connection. Een adapter achter delegated OAuth blijft aan die kant
gebruikersafhankelijk.

Bied uitsluitend vaste, geautoriseerde operaties aan; maak geen generieke proxy
waarmee consumers willekeurige API's onder de adapteridentiteit kunnen aanroepen.
Deze route voegt infrastructuur, beheer, monitoring en een extra vertrouwensgrens toe.

### Acceptatiecriteria voor app-only

Test naast een succesvolle aanroep expliciet:

- Uitvoering zonder delegated gebruikers-Connection of gebruikersaanmelding.
- De verwachte applicatie-identiteit, audience en applicatierol bij INET APIM.
- Afwijzing van delegated tokens, verkeerde applicaties, ontbrekende rollen en
  ontbrekende of ongeldige subscription keys.
- Credentialrotatie of Managed Identity-lifecycle en herhaalbare OTAP-deployment.

Een `roles`-claim alleen bewijst geen app-only context: gebruikertokens kunnen ook
rollen bevatten. Valideer de volledige tokencontext en toegestane identiteit.

## 4. Antwoorden op de oorspronkelijke vragen

### Stap 1 - API beschikbaar stellen door INET

**Hoe sluit de connector aan op subscription key en app-gebaseerde JWT-autorisatie,
bij voorkeur zonder tussenservice?**

De subscription key kan naast OAuth als beveiligde Connection-parameter worden
opgenomen. Een connectorpolicy stuurt deze als `Ocp-Apim-Subscription-Key`.
De Developer Portal-aanvraag en goedkeuring blijven het proces voor Producttoegang;
een connectorinstallatie verleent die toegang niet automatisch.

Zonder tussenservice werkt de huidige repo met delegated OAuth naar APIM en
app-only toegang vanaf APIM naar de backend. Daarvoor moet INET expliciet een
delegated ingang autoriseren; een bestaande uitsluitend app-only ingang kan niet
ongewijzigd worden gebruikt. Als ook bij binnenkomst in INET APIM een app-only JWT
verplicht is, zijn route B of C uit hoofdstuk 3 nodig.

Beheer abonnementen bij voorkeur per toepassing/team en omgeving. Een geldige key
en een geldig token moeten samen toegang geven tot uitsluitend de bedoelde
operaties; behandel ze niet als onderling uitwisselbare beveiligingsmiddelen.

**PoC-status:** key plus delegated JWT en app-only backendtoegang zijn live bewezen.
De menselijke Developer Portal-aanvraag en goedkeuring zijn niet doorlopen.

### Stap 2 - Custom Connector realiseren door PPE

**Ondersteunt een Custom Connector een Service Principal, en wat is daarvoor nodig?**

Een Entra-appregistratie kan de OAuth-client zijn, maar dat maakt het resulterende
API-token niet app-only. Native `client_credentials` wordt door ingebouwde generieke
Custom Connector-OAuth niet ondersteund. Een Service Principal voor deployment of
flow-eigenaarschap is wel mogelijk, maar staat los van Connection-authenticatie.

Bij reguliere delegated OAuth zijn een clientappregistratie, gedelegeerde
API-permissies/consent, redirect en clientcredential nodig. Een client secret is
bekend en eenvoudig in te richten, maar vereist beveiligde opslag en rotatie en
verwijdert de gebruikersafhankelijkheid niet. Voor een echte app-only SP gelden
de aparte routes en applicatierollen uit hoofdstuk 3.

**Is Managed Identity een alternatief, met welke voor- en nadelen en voorwaarden?**

Ja, als secretless alternatief voor het OAuth-clientsecret van de connector.
Voordelen zijn geen clientsecretrotatie en centraal federationbeheer. Nadelen zijn
de blijvende gebruikersaanmelding en de omgevingsspecifieke inrichting van
federation en redirects. Single-tenant appregistratie en een concrete tenant-GUID
zijn vereist. Naar de backend biedt APIM Managed Identity wel echte app-only
authenticatie, met toegekende applicatierollen.

**Is een VNet of aanvullende infrastructuur nodig?**

Nee, niet voor SP/MI-authenticatie zelf. Publiek bereikbaar APIM kan vanuit reguliere
Power Platform- en Dynamics 365/Dataverse-omgevingen worden gebruikt, mits rechten,
DLP, tenantbeleid en licenties dit toestaan. Private APIM-bereikbaarheid vereist
een afzonderlijke netwerkoplossing. Route C vereist daarnaast adapterinfrastructuur;
de delegated route niet. De PoC bewijst geen private netwerkroute of Dynamics UI-integratie.

**Welke methode heeft de voorkeur voor beheer, beveiliging en automatisering?**

Voor de huidige connectorarchitectuur: delegated OAuth met federation, APIM Managed
Identity naar de backend en Azure DevOps met Service Principal/WIF voor deployment.
Gebruik passende Dataverse application users en minimale benodigde bevoegdheden.
Voor volledig gebruikersvrije runtime met een app-only INET-ingang geldt de keuze
tussen B en C. WIF in de pipeline is geen oplossing voor runtime-Connection-authenticatie.

**Hoe maken of actualiseren we vanuit APIM een connector zonder instellingenverlies?**

Gebruik APIM als bron van het API-contract en beheer Power Platform-authenticatie,
Connection-parameters en policies afzonderlijk. De APIM-exportfunctie kan een
connector aanmaken of bijwerken, maar is geen garantie dat alle lokale instellingen
behouden blijven.

De updateprocedure moet bestaande properties downloaden, het bedoelde contract
wijzigen en de volledige relevante properties met de update meesturen.
Vergelijk daarna de effectieve definitie, authenticatie en policies.
In de PoC verwijderde een update zonder propertiesbestand de subscription-headerpolicy.
Zie [Update-ConnectorDefinition.ps1](../scripts/Update-ConnectorDefinition.ps1).
Gebruik de initiatiele auth-overlay niet om bestaande federated instellingen te overschrijven.

**Kunnen we de instellingen afzonderlijk beheren en via Azure DevOps toepassen?**

Ja, voor de definities, ondersteunde configuratie, federationregistratie en
solution-deployment. Beheer contract, auth/policies en omgevingsconfiguratie
afzonderlijk in versiebeheer, zonder secrets. Environment variables ondersteunen
onder andere host en OAuth-velden, maar worden bij opslaan geevalueerd; gewijzigde
waarden vereisen opnieuw opslaan. Ze worden niet ondersteund in connectoracties,
triggers of policies. Gebruik voor eventuele secrets daarvoor geschikte beveiligde
opslag, niet gewone tekstvariabelen.

Controleer na import de eigen federation en redirect van de doelomgeving; kopieer
niet blind die van Build. De initiatiele delegated aanmelding blijft een aparte
gebruikersstap. De [pipeline](../azure-pipelines.yml) is een nog niet live uitgevoerde
template en automatiseert de vastgelegde target-layercorrecties niet volledig.

### Stap 3 - Distributie door PPE

**Is Catalog geschikt voor meerdere omgevingen en developmentteams?**

Ja, als centrale vindplaats met publishers, goedkeuring en distributie van
herbruikbare managed items, waaronder custom connectors. Gebruik geen templatekopie
als centrale onderhoudbaarheid het doel is. Catalog gebruikt Dataverse en moet
vooraf met rollen en toegangsrechten worden ingericht. Publiceren vereist een
Managed Environment; consumerinstallatie vereist niet dezelfde publicatievoorwaarde.
De Developer-omgevingen van deze PoC zijn geen Managed Environments.

**Wat zijn de voor- en nadelen ten opzichte van directe managed deployments?**

| Aspect | Catalog | Directe managed solution-deployment |
|---|---|---|
| Gebruik | Discovery en selfservicehergebruik | Centraal geplande OTAP-promotie |
| Governance | Publishers, catalogusgoedkeuring en installatiehistorie | Pipeline-approvals en deploymentrechten |
| Updates | Expliciet installeren/bijwerken; geen automatische push | Pipeline bepaalt welke omgeving wanneer wordt bijgewerkt |
| Beheerlast | Extra catalogusinrichting en rollen | Minder aanvullende platforminrichting |

Advies: begin met directe managed deployments voor verplichte uitrol en voeg
Catalog toe voor discovery en onboarding. Catalog vervangt de ALM-pipeline niet.

**Hoe automatiseren we nieuwe connectors en updates, inclusief versies en afhankelijkheden?**

Gebruik Power Platform Build Tools/PAC met deze volgorde:

1. Haal het contract op, combineer de connectorconfiguratie en controleer compatibiliteit.
2. Werk de authoringconnector bij en valideer beveiligingsinstellingen en policies.
3. Verhoog de solutionversie en exporteer een versioned managed artifact.
4. Importeer eerst de centrale connectoroplossing.
5. Verifieer federation, effectieve definitie en lokale deel-/gebruiksrechten.
6. Importeer consumeroplossingen en bind bestaande lokale Connections via deployment settings.
7. Voer een echte runtime-smoketest uit met de bedoelde identiteit.

Catalog ondersteunt submit/install/status via PAC; specifieke Catalog Build Tools-taken
zijn als preview gedocumenteerd. Publiceer een nieuwe versie en orkestreer per
doelomgeving expliciet de installatie/update als centrale uitrol nodig is.

Leg ondersteunde connectorversies vast. Afhankelijkheidsregistratie voor custom
connectors heeft beperkingen: vertrouw niet op automatische afhandeling tussen
losse oplossingen of catalogusitems. Houd connector en consumers gescheiden en
laat consumers de connector niet opnieuw als eigen beheerd component meeleveren.
Behoud operation IDs en bestaande contracten bij compatibele updates; gebruik
voor breaking changes een expliciete versie-/migratiestrategie.

**Hoe voorkomen we dat lokale wijzigingen centrale updates verstoren?**

Beperk wijzigingsrechten, deel alleen de benodigde gebruiksrechten en houd centraal
eigenaarschap aan. Managed solutions alleen blokkeren niet alle lokale wijzigingen;
managed properties kennen connectorbeperkingen. Detecteer onverwachte Active layers
en controleer of de nieuwe definitie daadwerkelijk effectief wordt.

Maak onderscheid tussen ongewenste lokale edits en noodzakelijke omgevingsconfiguratie.
Verwijder Active layers niet blind: in deze PoC bevatten ze ook targetfederation.
Roltoewijzingen worden niet automatisch over omgevingen meegenomen en moeten lokaal
worden ingericht. Catalog-distributie is in deze repo nog niet live bewezen.

### Stap 4 - Gebruik door developmentteams

**Hoe richten we Connections veilig en automatisch in zonder credentials te delen?**

Voor de delegated connector kan PPE appregistratie, federation en keybeheer centraal
houden, zodat teams geen OAuth-clientsecret ontvangen. De gebruiker moet nog wel
de initiatiele OAuth-aanmelding doen. Een deployment settings-bestand bindt een
bestaande Connection aan een Connection Reference, maar maakt geen geldige
OAuth-Connection of gebruikersconsent aan.

PPE kan subscription keys centraal laten invoeren en beheren. Volledig automatische
keyprovisioning/rotatie zonder credentialoverdracht is echter niet bewezen.
Een Service Principal kan een flow bezitten of activeren met passende
Connection-gebruiksrechten; dat maakt de onderliggende authenticatie niet app-only.
Het delen van de connector is bovendien niet hetzelfde als het delen van een Connection.

Voor gebruikersvrije uitvoering moet route A, B of C expliciet worden gekozen.
Daarna moet de gekozen Connection-/credentialprovisioning apart worden bewezen.
Beperk ook bewerkrechten: verborgen credentials betekenen niet dat iedere gebruiker
veilig willekeurige bewerkingen met die identiteit mag uitvoeren.

**Hoe beheren we authenticatie en credentials per OTAP-omgeving?**

| Onderdeel | Omgevingsgebonden beheer |
|---|---|
| API-host en resource/audience | Ondersteunde environment variables of deploymentconfiguratie |
| Connectorfederation en redirect | Registreren en controleren per doelomgeving |
| Subscription key | Beveiligde lokale Connection, centrale rotatie en intrekking |
| Backendidentiteit en applicatierollen | Least privilege, passende scheiding tussen productie en niet-productie |
| Connection | Lokaal aanmaken, monitoren en zo nodig herstellen |
| Connection Reference | Stabiele logische naam, lokale binding via deployment settings |
| Pipeline-identiteit | WIF, Dataverse application user en omgevingsgebonden rechten |

Connections en credentials worden niet als werkende login tussen omgevingen
getransporteerd. Sla geen secrets op in Git, gewone tekst-environment variables
of logs. Een Connection Reference bevat een verwijzing, niet de credentials.

**Blijven Connections en References behouden zonder opnieuw authenticeren?**

Dat kan bij compatibele updates, mits connectoridentiteit, Connection-parameters,
OAuth-configuratie, targetfederation en bindings behouden blijven. De PoC bewijst
dit voor de vastgelegde update en twee succesvolle flowruns, na gecontroleerde
correcties; niet voor iedere toekomstige update.

Nieuwe consent, authenticatiewijzigingen, ingetrokken rechten, ongeldige keys of
Conditional Access kunnen herstel of herauthenticatie vereisen.
Test Canvas en Dynamics afzonderlijk: volgens Microsoft herkennen Canvas apps geen
Connection References voor custom connectors. De flowresultaten van deze repo
zijn daarom geen bewijs voor alle app- en Dynamics-scenario's.

## 5. Beslisadvies

| Harde eis | Voorkeursrichting |
|---|---|
| Custom Connector, gebruikerscontext toegestaan, geen extra tussenservice | Delegated aanpak van deze repo |
| Geen gebruikersafhankelijkheid, alleen achtergrondflows, app-only JWT bij INET | Route B onderzoeken en bewijzen |
| Custom Connector behouden en app-only JWT bij bestaande INET-ingang | Route C |
| Custom Connector behouden, geen extra infrastructuur, key-authenticatie toegestaan | Route A na securitygoedkeuring |

**Conclusie:** de huidige repo is een werkend voorbeeld van delegated toegang tot
APIM met app-only backendtoegang. Voor app-only vanuit de consumer is een andere
aanroeproute of een adapter nodig; alleen een SP, MI-instelling of ander
flow-eigenaarschap toevoegen is niet voldoende.

## Microsoft-bronnen

- [Custom Connector-authenticatie en beperking client credentials][auth]
- [Managed identity voor gedelegeerde connector-OAuth][connector-mi]
- [APIM-export en connectorupdates](https://learn.microsoft.com/azure/api-management/export-api-power-platform)
- [APIM Managed Identity naar backend](https://learn.microsoft.com/azure/api-management/authentication-managed-identity-policy)
- [PAC connector create/download/update](https://learn.microsoft.com/power-platform/developer/cli/reference/connector)
- [Connectorbeperkingen in solutions](https://learn.microsoft.com/connectors/custom-connectors/customconnectorssolutions)
- [Connection References en Canvas-beperkingen](https://learn.microsoft.com/power-apps/maker/data-platform/create-connection-reference)
- [Deployment settings voor bindings](https://learn.microsoft.com/power-platform/alm/conn-ref-env-variables-build-tools)
- [Environment variables: evaluatie bij opslaan](https://learn.microsoft.com/connectors/custom-connectors/environment-variables)
- [Azure DevOps Build Tools en WIF](https://learn.microsoft.com/power-platform/alm/devops-build-tools)
- [Service Principal-owned flows](https://learn.microsoft.com/power-automate/service-principal-support)
- [Catalog](https://learn.microsoft.com/power-apps/maker/data-platform/catalog-overview)
- [Catalog-inrichting en voorwaarden](https://learn.microsoft.com/power-platform/admin/administer-catalog)
- [Catalog-installaties en updates](https://learn.microsoft.com/power-platform/developer/catalog/install-items)
- [Build Tools-taken, inclusief Catalog](https://learn.microsoft.com/power-platform/alm/devops-build-tool-tasks)
- [Power Platform VNet-ondersteuning](https://learn.microsoft.com/power-platform/admin/vnet-support-overview)

[auth]: https://learn.microsoft.com/connectors/custom-connectors/connection-parameters
[connector-mi]: https://learn.microsoft.com/connectors/custom-connectors/azure-active-directory-authentication#managed-identity-authentication
