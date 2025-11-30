# ⚠️ Problème: CPU AMD - TDX Non Disponible

## Diagnostic

- **CPU:** AMD EPYC 9334 32-Core Processor
- **TDX:** Technologie Intel uniquement
- **Problème:** COCOON nécessite Intel TDX pour le mode production

## Situation

**Intel TDX (Trust Domain Extensions)** est une technologie Intel qui n'est pas disponible sur les CPUs AMD. COCOON est conçu pour fonctionner avec Intel TDX pour fournir la confidentialité et l'attestation requises.

## Options Possibles

### Option 1: Mode Test (Sans Confidentialité Complète)

COCOON peut fonctionner en mode test sans TDX, mais cela ne fournit pas les garanties de confidentialité requises pour la production:

```bash
cd /home/mika/cocoon/release-8728fe7
./scripts/cocoon-launch --test --fake-ton --no-tdx worker-0.conf
```

⚠️ **Note:** Ce mode est uniquement pour les tests et ne peut pas être utilisé pour la production réelle.

### Option 2: Utiliser un Serveur avec CPU Intel

Pour utiliser COCOON en production, vous avez besoin d'un serveur avec:
- **CPU Intel** avec support TDX (Sapphire Rapids ou plus récent)
- TDX activé dans le BIOS
- Kernel Linux 6.16+ avec support TDX

### Option 3: Vérifier le Support SEV (AMD)

AMD a sa propre technologie de confidentialité appelée **SEV-SNP** (Secure Encrypted Virtualization - Secure Nested Paging). Cependant, COCOON est actuellement conçu spécifiquement pour Intel TDX et ne supporte pas SEV-SNP.

## Recommandations

1. **Pour la production COCOON:** Utilisez un serveur avec CPU Intel et TDX activé
2. **Pour les tests:** Utilisez le mode `--test --fake-ton --no-tdx` (limitations importantes)
3. **Contactez COCOON:** Vérifiez s'ils prévoient un support pour AMD SEV-SNP dans le futur

## Documentation

- Intel TDX: https://www.intel.com/content/www/us/en/developer/articles/technical/intel-trust-domain-extensions.html
- AMD SEV: https://www.amd.com/en/developer/sev.html
- COCOON: https://cocoon.org/gpu-owners

## Résumé

Malheureusement, **COCOON ne peut pas fonctionner en mode production sur un CPU AMD** car il nécessite Intel TDX. Vous avez deux options:

1. **Utiliser un serveur Intel avec TDX** pour la production
2. **Utiliser le mode test** pour tester la configuration (sans confidentialité complète)

