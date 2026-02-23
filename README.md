# iastart - ISP AI Starter

Repositório para implantação automatizada de agentes de IA e ferramentas de atendimento para Provedores de Internet (ISPs).

## ⚠️ Requisitos Críticos

> [!IMPORTANT]
> **IP PÚBLICO VÁLIDO OBRIGATÓRIO** (a menos que use Cloudflare Tunnel)
> Para que o sistema funcione corretamente com acesso direto, o servidor **PRECISA** ter um endereço IP Público Válido nas portas 80 e 443.
>
> Se você estiver atrás de um CGNAT ou Firewall restritivo, use a opção `--tunnel` para acesso via Cloudflare Tunnel (sem portas abertas).

> [!NOTE]
> **Compatibilidade**: O script de instalação foi testado e validado no **Debian 13**.

## Tecnologias

- **Docker Swarm**: Orquestração
- **Traefik**: Proxy Reverso e SSL
- **Portainer**: Gestão Visual
- **Apps**: n8n, Chatwoot, Evolution API
- **Opcionais**: WordPress, OpenClaw (AI Assistant), Cloudflare Tunnel
- **Bancos**: PostgreSQL, MySQL (opcional), Redis, MinIO

## 🚀 Instalação Rápida

1. **Clone o repositório**

   ```bash
   git clone https://github.com/tnarnold/iastart.git
   cd iastart
   ```

2. **Configure as Variáveis de Ambiente**
   Copie o exemplo e edite com seus dados (Domínio, Senhas, Emails):

   ```bash
   cp .env.example .env
   nano .env
   ```

   > **Nota:** Defina senhas fortes para produção!

3. **Execute o Script de Instalação**
   Executar com o root este script que fará todo o processo: desde a instalação do Docker até o deploy das aplicações.
   ```bash
   bash install.sh
   ```

### Modos de Instalação

| Comando                                | O que instala                                                                                         |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `bash install.sh`                      | **Completa** — Docker, Traefik, Portainer, PostgreSQL, MinIO, Redis e Apps (n8n, Chatwoot, Evolution) |
| `bash install.sh --no-apps`            | **Infra + Bancos** — Docker, Traefik, Portainer, Redis, PostgreSQL, MinIO                             |
| `bash install.sh --no-databases`       | **Somente Infra** — Docker, Traefik, Portainer                                                        |
| `bash install.sh --wordpress`          | **Core + CMS** — Tudo acima + MySQL e WordPress                                                       |
| `bash install.sh --openclaw`           | **Core + OpenClaw** — Tudo acima + AI Assistant                                                       |
| `bash install.sh --tunnel`             | **Core + Tunnel** — Tudo acima + Cloudflare Tunnel                                                    |
| `bash install.sh --wordpress --tunnel` | **Exemplo Combinado** — Completa + CMS + Tunnel                                                       |

> **Nota:** `--no-databases` implica `--no-apps`. As flags `--wordpress`, `--openclaw` e `--tunnel` podem ser combinadas com qualquer modo.

Para ver todas as opções:

```bash
bash install.sh --help
```

## Acesso aos Serviços

Após a instalação (aguarde alguns minutos para tudo subir), você poderá acessar:

- **Traefik Dashboard**: `http://<SEU-IP>:8080`
- **Portainer**: `https://<SEU-IP>:9443`
- **n8n**: `https://wf.seudominio.com.br`
- **Chatwoot**: `https://chat.seudominio.com.br`
- **Evolution API**: `https://ws.seudominio.com.br`
- **MinIO Console**: `https://cdn.seudominio.com.br`
- **WordPress** (se `--wordpress`): `https://app.seudominio.com.br`
- **OpenClaw** (se `--openclaw`): `https://ai.seudominio.com.br`

## Estrutura de Pastas e arquivos

- `01-docker.sh`: Instalação base Docker/Swarm
- `04-cloudflared.sh`: Setup automático do Cloudflare Tunnel
- `install.sh`: Script mestre de automação
- `chatwoot/`, `04-n8n/`: Configurações específicas das apps

## Solução de Problemas

Se o SSL não funcionar (cadeado vermelho ou erro de certificado):

1. Verifique se o seu domínio aponta para o IP correto do servidor (Tipo A).
2. Verifique se as portas 80 e 443 estão liberadas no Firewall do provedor de nuvem (AWS/DigitalOcean/etc).
3. Verifique os logs do Traefik: `docker service logs -f traefik_traefik`.

## ☁️ Cloudflare Tunnel (Acesso sem portas abertas)

Se o seu servidor está atrás de CGNAT ou não tem IP público, use o Cloudflare Tunnel:

1. **Crie um API Token** no [dashboard Cloudflare](https://dash.cloudflare.com/profile/api-tokens) com:
   - `Account > Cloudflare Tunnel > Edit`
   - `Zone > DNS > Edit`

2. **Obtenha seu Account ID** na visão geral do domínio no dashboard

3. **Configure no `.env`**:

   ```env
   CF_ACCOUNT_ID=seu_account_id
   CF_TUNNEL_API_TOKEN=seu_api_token
   ```

4. **Instale com tunnel** ou rode separadamente:
   ```bash
   bash install.sh --tunnel        # Durante instalação
   bash 04-cloudflared.sh           # Separadamente
   bash 04-cloudflared.sh --delete  # Remover tunnel
   ```

## 🗺️ Roadmap

- [x] **Cloudflare Tunnel**: Acesso externo sem portas abertas via Tunnel.
- [ ] **Reorganização**: Melhorar estrutura de arquivos e diretórios.
- [ ] **Menu Interativo**: Criar instalador com seleção de serviços.
- [ ] **Firewall de Gerência**: Restringir acesso às portas de gerência.
