# 🔐 Fechadura Eletrônica – Projeto PSD

## 📌 Resumo  
Este projeto implementa uma **fechadura eletrônica** no modelo de sobrepor, capaz de armazenar até **4 PINs diferentes** para destravamento.  
O sistema monitora o estado da porta e alerta o usuário caso ela fique aberta por muito tempo, emitindo um **bip sonoro**. Além disso, realiza o **travamento automático** após um tempo configurável.  

---

## ⚙️ Componentes do Sistema
- ⌨️ **Teclado Matricial 4x4** → Inserção dos PINs.  
- 🖥️ **6 Displays de 7 Segmentos**  
  - Exibem os dígitos inseridos.  
  - No modo de configuração, mostram opções/estados.  
- 🔑 **Chave de Contato** → Detecta porta aberta/fechada.  
- 🔘 **Botão Interno** → Liberação da tranca pelo lado de dentro.  
- 💡 **LED** → Indica se a fechadura está trancada.  

---

## 🖥️ Modos de Operação

### 🔹 Modo Operacional
- Aguarda PIN inserido via teclado.  
- Verifica PIN somente após tecla `*`.  
- Se válido → destrava a fechadura.  
- Se inválido → bloqueia entrada por 1s e mostra `- - - - -`.  
- Após 3 erros → tempos de bloqueio crescentes (10s, 20s, 30s).  
- Master PIN → alterna para **modo configuração**.  
- Travamento automático:  
  - Porta fechada → trava após tempo configurável (5s padrão).  
  - Porta aberta → inicia contagem para bip contínuo.  

### 🔹 Modo Setup (Configuração)
Permite ajustar parâmetros:  
1. Ativar/desativar o bip.  
2. Definir tempo para bipar (5–60s).  
3. Definir tempo de travamento automático (5–60s).  
4. Gerenciar até 4 PINs (ativar/desativar/alterar).  

---

## 🔄 Reset
- Reset válido apenas se botão for pressionado por **5 segundos**.  
- Restaura configurações padrão:  
  - PIN1 ativo com valor `0000`.  
  - Master PIN `1234` (solicita redefinição).  
  - Bip ativado.  
  - Tempos de bip/trava = **5s**.  

---

## 🧩 Estruturas de Dados
- **`pinPac_t`** → Representa um PIN (status + 4 dígitos).  
- **`bcdPac_t`** → Representa os valores dos displays em BCD.  
- **`setupPac_t`** → Configurações globais (bip, tempos, PINs).  

---

## 🏗️ Arquitetura do Sistema
O sistema é modular, com os seguintes blocos principais:  

- **FechaduraTop** → Módulo principal, integra todos os submódulos.  
- **Operacional** → Controla o fluxo normal de funcionamento.  
- **Setup** → Implementa o modo de configuração.  
- **MontarPin** → Recebe teclas, monta o PIN e sinaliza quando pronto.  
- **VerificarSenha** → Valida PINs (padrão ou master).  
- **UpdateMaster** → Atualiza o master PIN após reset.  
- **ResetHold5s** → Garante reset válido apenas após 5s pressionado.  
- **MatrixKeyDecoder** → Faz leitura, debounce e decodificação do teclado matricial.  
- **SixDigit7SegCtrl** → Controla os displays de 7 segmentos.  

---

## 📊 Fluxo Simplificado
```mermaid
flowchart TD
    A[⌨️ Teclado Matricial] --> B[MontarPin]
    B --> C[VerificarSenha]
    C -->|Senha Padrão| D[🔓 Destrava Fechadura]
    C -->|Senha Master| E[⚙️ Modo Setup]
    E -->|Configurações| F[Atualiza setupPac_t]
    D --> G[Controle Porta e Trava Automática]
    G --> H[🔔 Bip Sonoro / 💡 LED]
