# Auditoria de segurança da informação em uma loja virtual

Atividade da disciplina de Auditoria e Segurança de Sistemas de Informação da especialização em Desenvolvimento Web e Mobile do IF Sudeste de Minas Gerais. Analisei o Sistema de Gestão da Segurança da Informação (SGSI) da Loja Virtual LTDA e verifiquei controles em uma VM de laboratório que hospedava a loja WordPress com WooCommerce, MariaDB, Apache e PHP. A coleta foi realizada em **21 de novembro de 2026**, no horário de Brasília.

## Escopo e critérios

Usei o SGSI v1.0 como critério documental e preservei a numeração do checklist da disciplina. A ISO/IEC 27001:2013 orientou a leitura dos requisitos do SGSI, a ISO/IEC 27002:2013 serviu de referência para os controles e a ISO/IEC 27007:2020 orientou o registro e a avaliação das evidências. [ISO/IEC 27001](https://www.iso.org/standard/54534.html) · [ISO/IEC 27002](https://www.iso.org/standard/54533.html) · [ISO/IEC 27007](https://www.iso.org/standard/77802.html)

## Coleta na VM

Executei o coletor às 16h20 como usuário comum e repeti às 16h29 com `sudo`. A primeira execução registrou acesso parcial a `/var/www`. A segunda identificou a instalação do WordPress em `/var/www/ecommerce` e serviu de base para a avaliação técnica. Complementei a coleta com verificações no navegador.

| Evidência | Arquivos |
| --- | --- |
| Coleta com usuário comum | [CSV](evidencias/coleta-sem-sudo/evidencias-auditoria.csv) · [HTML](evidencias/coleta-sem-sudo/evidencias-auditoria.html) |
| Coleta com privilégios administrativos | [CSV](evidencias/coleta-com-sudo/evidencias-auditoria.csv) · [HTML](evidencias/coleta-com-sudo/evidencias-auditoria.html) |
| WordPress | [Painel de atualizações](evidencias/wordpress-atualizacoes.png) · [Negativa de acesso](evidencias/wordpress-acesso-negado.png) |

O CSV pode ser importado no Calc usando `;` como separador. Para visualizar o HTML renderizado, baixe o arquivo e abra-o no navegador. As capturas foram recortadas para preservar o conteúdo relevante da tela.

### Como executar o coletor

O [script](coletar_auditoria_vm.sh) foi usado no Ubuntu 22.04.5 LTS. Ele requer Bash e Python 3. O inventário de pacotes usa APT e dpkg, e a consulta a serviços usa systemd.

```bash
bash ./coletar_auditoria_vm.sh
```

Em uma VM própria ou autorizada, execute com `sudo` quando a coleta precisar acessar diretórios e registros protegidos.

```bash
sudo bash ./coletar_auditoria_vm.sh --wp-path /var/www/ecommerce
```

Use `--backup-dir` para acrescentar um diretório à busca e `--saida` para indicar um diretório de saída já existente. O script cria uma nova pasta por execução e grava nela `evidencias-auditoria.csv` e `evidencias-auditoria.html`. Se a execução for feita com `sudo`, os arquivos podem ficar acessíveis apenas ao administrador.

### Como o script funciona

O Bash verifica a presença do Python 3 e executa `exec python3 - "$@" <<'PY'`. O *here-document* fornece o código Python pela entrada padrão. As aspas no delimitador impedem que o Bash interprete expressões dentro do bloco, e `"$@"` repassa os argumentos da linha de comando.

O Python usa `subprocess.run()` para capturar a saída dos comandos. Consulta `/etc/os-release`, lê o inventário com `dpkg-query -W`, verifica candidatas com `apt-cache policy`, compara revisões com `dpkg --compare-versions` e procura atualizações nos logs do dpkg. O estado dos serviços é consultado com `systemctl show`. Para WordPress e WooCommerce, o coletor extrai as versões dos arquivos da instalação.

Cada verificação gera um registro com ID, controle, verificação, situação, evidência e fonte. A mesma lista alimenta `csv.writer()`, que grava o CSV delimitado por ponto e vírgula, e a geração do HTML, que agrupa as linhas por controle e usa `html.escape()` nos valores das células. A execução faz consultas locais e grava os arquivos de evidência. As conclusões do checklist são resultado da avaliação desses registros e dos testes manuais.

## Checklist

**Sem evidência** indica que a implementação não pôde ser confirmada com o material disponível. **Parcial** indica que parte do controle foi verificada ou implementada, com lacunas identificadas.

### Documento SGSI

| Código | Controle | Implementado? | Base da avaliação |
| --- | --- | --- | --- |
| 5 | Política de Segurança da Informação | Sem evidência | O SGSI menciona a política na seção 1. O texto da política não foi apresentado. |
| 6.1.1 | Responsabilidades e papéis pela segurança da informação | Sim | A seção 5.1 atribui responsáveis funcionais aos ativos do escopo. |
| 8.1.1 | Inventário dos ativos | Sim | A seção 5.1 lista o banco, o sistema da loja e a hospedagem. |
| 8.1.2 | Proprietário dos ativos | Sim | No checklist entregue, os responsáveis funcionais da seção 5.1 foram aceitos como atribuição de responsabilidade pelos ativos no escopo. |
| 8.2.1 | Classificação da informação | Parcial | A seção 5.2 atribui notas de confidencialidade, integridade e disponibilidade. As classes de informação não estão formalizadas. |
| 8.2.3 | Tratamento dos ativos | Parcial | A seção 5.4 lista controles e responsáveis. Faltam regras de manuseio por classificação. |
| 9.4.2 | Procedimentos seguros de entrada no sistema (log-on) | Sem evidência | O SGSI fornecido não apresenta um procedimento documentado. |
| 9.4.3 | Sistema de gerenciamento de senha | Sem evidência | O SGSI fornecido não apresenta os requisitos de gerenciamento de senhas. |

### Controles na VM

| Controle | Implementado? | Evidência |
| --- | --- | --- |
| Backup do banco de dados | Sem evidência | Zero arquivos candidatos em `/var/backups` e zero referências diretas a utilitários de backup nos arquivos cron legíveis. [Coleta com sudo](evidencias/coleta-com-sudo/evidencias-auditoria.csv) |
| Teste do backup do banco de dados | Sem evidência | Nenhum registro de restauração foi apresentado. |
| Atualização do gerenciador do banco de dados | Não | MariaDB 10.6.22 instalado e 10.6.23 indicado como candidato no índice local. [Coleta com sudo](evidencias/coleta-com-sudo/evidencias-auditoria.csv) |
| Atualização do sistema web LojaVirtual | Parcial | Núcleo atualizado segundo o painel, com 9 plugins e 5 temas pendentes. [Atualizações do WordPress](evidencias/wordpress-atualizacoes.png) |
| Controle de acesso/usuário | Sim | A página de atualizações abriu para a conta administrativa e recusou o acesso da conta comum no teste registrado no relatório. [Negativa de acesso](evidencias/wordpress-acesso-negado.png) |
| Atualização do sistema de hospedagem de páginas | Parcial | O histórico mostrou atualizações do Apache e do PHP, mas havia revisões de segurança posteriores para ambos. [Coleta com sudo](evidencias/coleta-com-sudo/evidencias-auditoria.csv) |

## Análise dos resultados

### Atualizações

O arquivo de índice APT mais recente na VM era de 30/09/2026. Comparei as revisões completas dos pacotes com os avisos da Canonical publicados até 21/11/2026. Essa comparação leva em conta que o Ubuntu pode incorporar correções mantendo o número-base do software. As lacunas abaixo foram identificadas por comparação de revisões. A exposição efetiva depende da configuração e das condições de uso. [Atualizações de segurança do Ubuntu](https://documentation.ubuntu.com/security/security-updates/)

| Componente | Revisão coletada | Avaliação na data da auditoria |
| --- | --- | --- |
| MariaDB | `1:10.6.22-0ubuntu0.22.04.1` | A revisão `1:10.6.23-0ubuntu0.22.04.1` estava disponível no índice local. A revisão instalada já incluía a correção da CVE-2025-30693. A CVE-2026-85746, corrigida na versão comunitária 10.6.28, ainda constava como pendente de avaliação para o MariaDB 10.6 do Jammy. [Pacote Jammy](https://packages.ubuntu.com/jammy-updates/mariadb-server-10.6) · [USN-7519-1](https://ubuntu.com/security/notices/USN-7519-1) · [MariaDB 10.6.28](https://mariadb.com/docs/release-notes/community-server/10.6/10.6.28) · [CVE-2026-85746](https://ubuntu.com/security/CVE-2026-85746) |
| Apache | `2.4.52-1ubuntu4.23` | O aviso de 12/11 publicou a revisão `2.4.52-1ubuntu4.27` para o Jammy, com a correção da CVE-2026-109163. [USN-9090-1](https://ubuntu.com/security/notices/USN-9090-1) · [CVE-2026-109163](https://ubuntu.com/security/CVE-2026-109163) |
| Módulo PHP do Apache | `8.1.2-1ubuntu2.26` | O aviso de 21/10 publicou a revisão `8.1.2-1ubuntu2.28`, com correções para as CVE-2026-109618 e CVE-2026-109619. [USN-8948-1](https://ubuntu.com/security/notices/USN-8948-1) · [CVE-2026-109618](https://ubuntu.com/security/CVE-2026-109618) · [CVE-2026-109619](https://ubuntu.com/security/CVE-2026-109619) |
| Ubuntu e kernel | Ubuntu 22.04.5 LTS | A coleta identificou a distribuição. A versão do kernel em execução não foi registrada, então a aplicabilidade das CVEs de kernel à VM ficou em aberto. [Suporte do Ubuntu](https://ubuntu.com/security/esm) · [Aviso da linha GA](https://ubuntu.com/security/notices/USN-9167-1) · [Aviso da linha HWE](https://ubuntu.com/security/notices/USN-9066-1) |

O painel WordPress registrou o núcleo `7.1.5` como atualizado. Entre as 14 pendências estavam o WooCommerce `11.1.2 → 11.3.1` e o tema eStore `1.6.12 → 1.6.14`. O painel indica a disponibilidade de versões e não estabelece, por si só, quais CVEs se aplicam às extensões instaladas. [Captura do painel](evidencias/wordpress-atualizacoes.png)

### Backup e restauração

O coletor procura nomes e metadados de arquivos compatíveis com cópias de banco, até quatro níveis abaixo dos diretórios consultados. A coleta com `sudo` registrou apenas `/var/backups` como diretório inspecionado. A busca no cron cobre os arquivos legíveis em caminhos como `/etc/crontab`, `/etc/cron.d` e `/var/spool/cron/crontabs`. O resultado não cobre de forma conclusiva scripts intermediários, timers do systemd, plugins ou cópias externas. A capacidade de restaurar dados e pedidos permaneceu sem comprovação.

### Controle de acesso

Testei a página administrativa de atualizações do WordPress. A conta administrativa abriu a página e a conta comum, em uma janela privativa, recebeu a mensagem “Sem permissão para acessar esta página”. O resultado se limita à função testada. A captura comprova a negativa, e o relatório registra o tipo de conta usado no teste. [Captura da negativa](evidencias/wordpress-acesso-negado.png)

## Recomendações

1. Priorizar as atualizações do Apache e do PHP, revisar as extensões do WordPress e validar o funcionamento da loja após as mudanças. Atualizar o índice APT em uma janela de manutenção e registrar separadamente o kernel em execução com `uname -r`.
2. Confirmar os destinos realmente usados para backup, incluindo volumes montados, timers, plugins e armazenamento externo. Formalizar frequência, retenção e responsabilidades. Testar a restauração em ambiente isolado e registrar a abertura do banco e a conferência de dados representativos, como pedidos e produtos. Planejar a atualização do MariaDB com a recuperação previamente verificada. [Documentação de backup e restauração do MariaDB](https://mariadb.com/docs/server/server-usage/backup-and-restore/backup-and-restore-overview)
3. Disponibilizar a política aprovada, formalizar a classificação e o tratamento das informações e documentar os procedimentos de entrada segura e gerenciamento de senhas. Nos próximos testes de acesso, registrar o perfil da conta e a função avaliada sem expor dados pessoais.
