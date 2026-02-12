# iastart - ISP AI Starter

Repositório para implantação automatizada de agentes de IA e ferramentas de atendimento para Provedores de Internet (ISPs).

## ⚠️ Requisitos Críticos

> [!IMPORTANT]
> **IP PÚBLICO VÁLIDO OBRIGATÓRIO**
> Para que o sistema funcione corretamente, especialmente a geração de certificadoss SSL (HTTPS) pelo Traefik, este servidor **PRECISA** ter um endereço IP Público Válido e acessível externamente nas portas 80 e 443.
>
> Se você estiver atrás de um CGNAT ou Firewall restritivo, o SSL do Let's Encrypt falhará e os serviços não ficarão acessíveis.

> [!NOTE]
> **Compatibilidade**: O script de instalação foi testado e validado no **Debian 13**.

## Tecnologias

- **Docker Swarm**: Orquestração
- **Traefik**: Proxy Reverso e SSL
- **Portainer**: Gestão Visual
- **Apps**: n8n, Chatwoot, Evolution API, WordPress
- **Bancos**: PostgreSQL, MySQL, Redis, MinIO

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

| Comando | O que instala |
|---|---|
| `bash install.sh` | **Completa** — Docker, Traefik, Portainer, Bancos e Apps |
| `bash install.sh --no-apps` | **Infra + Bancos** — Docker, Traefik, Portainer, Redis, PostgreSQL, MinIO, MySQL |
| `bash install.sh --no-databases` | **Somente Infra** — Docker, Traefik, Portainer |

> **Nota:** `--no-databases` implica `--no-apps`, pois as aplicações dependem dos bancos de dados.

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
- **WordPress**: `https://app.seudominio.com.br`

## Estrutura de Pastas e arquivos

- `01-docker.sh`: Instalação base Docker/Swarm
- `install.sh`: Script mestre de automação
- `chatwoot/`, `04-n8n/`: Configurações específicas das apps

## Solução de Problemas

Se o SSL não funcionar (cadeado vermelho ou erro de certificado):
1. Verifique se o seu domínio aponta para o IP correto do servidor (Tipo A).
2. Verifique se as portas 80 e 443 estão liberadas no Firewall do provedor de nuvem (AWS/DigitalOcean/etc).
3. Verifique os logs do Traefik: `docker service logs -f traefik_traefik`.

## 🗺️ Roadmap

- [ ] **SSL Cloudflare**: Adicionar suporte a DNS Challenge (API Cloudflare) no Traefik.
- [ ] **Reorganização**: Melhorar estrutura de arquivos e diretórios.
- [ ] **Menu Interativo**: Criar instalador com seleção de serviços (O que instalar).
- [ ] **Firewall de Gerência**: Restringir acesso às portas de gerência dos aplicativos administrativos.