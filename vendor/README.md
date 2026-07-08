# vendor/

Dependencias de terceros vendorizadas en el repo (no vía pip).

## mitogen-0.3.50

Plugin de estrategia de Ansible que multiplexa Python sobre una sola conexión SSH
por host, acortando el tiempo de ejecución. Ver <https://mitogen.networkgenomics.com/ansible_detailed.html>.

- **Versión**: 0.3.50
- **Origen**: <https://files.pythonhosted.org/packages/source/m/mitogen/mitogen-0.3.50.tar.gz>
- **sha256** (tarball): `f8a97202c624d2e4c20960210a9e479fc59aca7ca26754ab34e1e08558b65d7c`
- **Plugins**: `mitogen-0.3.50/ansible_mitogen/plugins/strategy/`
- **Compatibilidad**: requiere ansible-core >= 2.10 (sin tope superior; 0.3.50
  contempla ansible-core hasta 2.20). Python 2.7 / 3.6–3.14 en control y target.

### Activar / desactivar

En `ansible.cfg`, bajo `[defaults]`, comentar/descomentar el bloque Mitogen
(dos líneas: `strategy_plugins` y `strategy`). Comentado = Ansible vanilla (default).

### Re-vendorizar (actualizar versión)

```bash
V=0.3.50   # cambiar por la versión deseada
curl -sSL -o /tmp/mitogen-$V.tar.gz \
  https://files.pythonhosted.org/packages/source/m/mitogen/mitogen-$V.tar.gz
tar -xzf /tmp/mitogen-$V.tar.gz -C vendor/
# Actualizar la ruta de strategy_plugins en ansible.cfg y la versión en este README.
```
