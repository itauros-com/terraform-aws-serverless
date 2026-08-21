#!/bin/bash

# Terraform Wrapper Functions
# Source questo file per avere accesso alle funzioni tfi, tfa, tfp, tfd
# Usage: source scripts/terraform-wrapper.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="/tmp/tfvars-sync"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variabili globali per configurazione S3
BUCKET=""
KEY_BASE=""
WORKSPACE_KEY_PREFIX=""
REGION=""

tf_log() {
    echo -e "${BLUE}[TF]${NC} $1"
}

tf_warn() {
    echo -e "${YELLOW}[TF-WARN]${NC} $1"
}

tf_error() {
    echo -e "${RED}[TF-ERROR]${NC} $1"
    return 1
}

tf_success() {
    echo -e "${GREEN}[TF-SUCCESS]${NC} $1"
}

# Ottiene il workspace corrente di terraform
get_current_workspace() {
    terraform workspace show 2>/dev/null
}

# Controlla dipendenze necessarie
check_dependencies() {
    tf_log "Controllo dipendenze..."

    if ! command -v aws &> /dev/null; then
        tf_error "AWS CLI non trovato. Installa AWS CLI e configura le credenziali."
        return 1
    fi

    if ! command -v hcl2json &> /dev/null; then
        tf_warn "hcl2json non trovato. Installa con: go install github.com/tmccombs/hcl2json@latest"
        tf_warn "Uso configurazione hardcoded per S3"
        return 0
    fi

    if ! command -v jq &> /dev/null; then
        tf_error "jq non trovato. Installa jq."
        return 1
    fi

    if ! aws sts get-caller-identity &> /dev/null; then
        tf_error "Credenziali AWS non configurate o non valide."
        return 1
    fi

    tf_success "Dipendenze OK"
    return 0
}

# Parse configurazione Terraform da providers.tf
parse_terraform_config() {
    local providers_file="$1"
    tf_log "Lettura configurazione da providers.tf..."

    if [ ! -f "$providers_file" ]; then
        tf_warn "File providers.tf non trovato, uso configurazione default"
        BUCKET="terraform-state-bucket"
        KEY_BASE="terraform.tfstate"
        WORKSPACE_KEY_PREFIX="env:"
        REGION="eu-west-1"
        return 0
    fi

    if ! command -v hcl2json &> /dev/null || ! command -v jq &> /dev/null; then
        tf_warn "hcl2json o jq mancanti, uso configurazione default"
        BUCKET="terraform-state-bucket"
        KEY_BASE="terraform.tfstate"
        WORKSPACE_KEY_PREFIX="env:"
        REGION="eu-west-1"
        return 0
    fi

    local bucket key workspace_key_prefix region

    read bucket key workspace_key_prefix < <(
        hcl2json "$providers_file" 2>/dev/null | jq -r '.terraform[].backend.s3[] | [.bucket, .key, .workspace_key_prefix] | @tsv' 2>/dev/null || echo "terraform-state-bucket terraform.tfstate env:"
    )

    region=$(hcl2json "$providers_file" 2>/dev/null | jq -r '.terraform[].backend.s3[].region // "eu-west-1"' 2>/dev/null || echo "eu-west-1")

    BUCKET="${bucket:-terraform-state-bucket}"
    KEY_BASE="${key:-terraform.tfstate}"
    WORKSPACE_KEY_PREFIX="${workspace_key_prefix:-env:}"
    REGION="${region:-eu-west-1}"

    tf_success "Configurazione estratta da providers.tf"
    return 0
}

# Sincronizza tfvars avanzato con diff e opzioni interattive
sync_tfvars() {
    local workspace="$1"

    # Calcola paths dinamicamente dalla directory corrente
    local tfvars_dir="$(pwd)/tfvars"
    local providers_file="$(pwd)/providers.tf"

    tf_log "Sincronizzazione workspace: $workspace"

    # Parse configurazione se non già fatto
    if [ -z "$BUCKET" ]; then
        # Passa il path del providers.tf alla funzione
        if ! parse_terraform_config "$providers_file"; then
            return 1
        fi
    fi

    # Costruisci paths dopo aver caricato la configurazione
    local s3_key="${WORKSPACE_KEY_PREFIX}/${workspace}/${KEY_BASE}.tfvars"
    local local_file="$tfvars_dir/${workspace}.tfvars"
    local temp_file="$TEMP_DIR/${workspace}.tfvars"

    # Crea directory necessarie
    mkdir -p "$tfvars_dir"
    mkdir -p "$TEMP_DIR"

    # Download da S3
    if aws s3 cp "s3://${BUCKET}/${s3_key}" "$temp_file" --region "$REGION" &> /dev/null; then
        tf_log "File scaricato da S3: $s3_key"
    else
        tf_warn "File non trovato su S3: $s3_key"

        if [ -f "$local_file" ]; then
            # Esporta subito il path del file tfvars
            export TF_CURRENT_TFVARS="$local_file"

            echo "File locale esistente. Vuoi caricarlo su S3?"
            echo -n "Carica $workspace.tfvars su S3? (y/N): "
            read upload_choice
            if [[ $upload_choice =~ ^[Yy]$ ]]; then
                aws s3 cp "$local_file" "s3://${BUCKET}/${s3_key}" --region "$REGION"
                tf_success "File caricato su S3: $s3_key"
            else
                tf_error "Sincronizzazione annullata dall'utente"
                return 1
            fi
        else
            tf_error "File tfvars non trovato né su S3 né localmente"
            return 1
        fi
        return 0
    fi

    # Confronta con file locale
    if [ ! -f "$local_file" ]; then
        tf_warn "File locale $workspace.tfvars non esiste"
        echo -n "Creare il file locale da S3? (y/N): "
        read create_choice
        if [[ $create_choice =~ ^[Yy]$ ]]; then
            cp "$temp_file" "$local_file"
            tf_success "File locale creato: $workspace.tfvars"
        fi
    elif ! cmp -s "$temp_file" "$local_file"; then
        tf_warn "File $workspace.tfvars ha differenze"

        echo
        echo -e "${BLUE}=== Differenze per $workspace.tfvars ===${NC}"
        if command -v colordiff &> /dev/null; then
            diff -u "$local_file" "$temp_file" | colordiff || true
        else
            diff -u "$local_file" "$temp_file" || true
        fi

        echo
        echo "Opzioni per $workspace.tfvars:"
        echo "1) Sovrascrivere il file locale con quello da S3"
        echo "2) Aggiornare S3 con il file locale"
        echo "3) Saltare questo workspace"

        while true; do
            echo -n "Scegli un'opzione (1-3): "
            read choice
            case $choice in
                1)
                    cp "$temp_file" "$local_file"
                    tf_success "File locale sovrascritto"
                    break
                    ;;
                2)
                    aws s3 cp "$local_file" "s3://${BUCKET}/${s3_key}" --region "$REGION"
                    tf_success "File caricato su S3"
                    break
                    ;;
                3)
                    tf_warn "Workspace saltato"
                    break
                    ;;
                *)
                    echo "Opzione non valida. Scegli 1, 2 o 3."
                    ;;
            esac
        done
    else
        tf_success "File $workspace.tfvars già allineato"
    fi

    # Esporta il path del file tfvars per le altre funzioni
    export TF_CURRENT_TFVARS="$local_file"

    return 0
}


# Cleanup file temporanei
cleanup_temp() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        tf_log "File temporanei rimossi"
    fi
}

# Trap per cleanup
trap cleanup_temp EXIT

# Funzione comune per preparare l'ambiente terraform
tf_prepare() {
    local command="$1"

    # Ottiene workspace corrente
    local workspace
    workspace=$(get_current_workspace)

    if [ $? -ne 0 ] || [ -z "$workspace" ]; then
        tf_error "Impossibile determinare il workspace corrente. Esegui 'terraform workspace select <workspace>' prima"
        return 1
    fi

    if [ "$workspace" = "default" ]; then
        tf_error "Non puoi usare il workspace 'default'. Seleziona un workspace specifico con 'terraform workspace select <workspace>'"
        return 1
    fi

    tf_log "Workspace corrente: $workspace"

    # Controlla dipendenze prima della sincronizzazione
    if ! check_dependencies; then
        tf_error "Dipendenze mancanti"
        return 1
    fi

    # Sincronizza tfvars
    if ! sync_tfvars "$workspace"; then
        tf_error "Errore nella sincronizzazione tfvars"
        return 1
    fi

    tf_success "Ambiente preparato per $workspace"

    # Esporta solo il workspace
    export TF_CURRENT_WORKSPACE="$workspace"

    return 0
}

# Rimuove alias esistenti per permettere la definizione delle funzioni
unalias tfi tfp tfa tfd tfw tfws tfh 2>/dev/null || true

# Terraform Init
tfi() {
    tf_log "Esecuzione: terraform init $*"
    terraform init "$@"
}

# Terraform Plan
tfp() {
    if ! tf_prepare "plan"; then
        return 1
    fi

    tf_log "Esecuzione: terraform plan -var-file=\"$TF_CURRENT_TFVARS\" $*"
    terraform plan -var-file="$TF_CURRENT_TFVARS" "$@"
}

# Terraform Apply
tfa() {
    if ! tf_prepare "apply"; then
        return 1
    fi

    tf_log "Esecuzione: terraform apply -var-file=\"$TF_CURRENT_TFVARS\" $*"
    terraform apply -var-file="$TF_CURRENT_TFVARS" "$@"

    local apply_result=$?

    if [ $apply_result -eq 0 ]; then
        tf_success "Apply completato con successo"
    fi

    return $apply_result
}

# Terraform Destroy
tfd() {
    if ! tf_prepare "destroy"; then
        return 1
    fi

    tf_warn "ATTENZIONE: Stai per distruggere l'infrastruttura del workspace $TF_CURRENT_WORKSPACE"
    read -p "Sei sicuro di voler continuare? Digita 'yes' per confermare: " confirm

    if [ "$confirm" != "yes" ]; then
        tf_log "Destroy annullato"
        return 0
    fi

    tf_log "Esecuzione: terraform destroy -var-file=\"$TF_CURRENT_TFVARS\" $*"
    terraform destroy -var-file="$TF_CURRENT_TFVARS" "$@"
}

# Lista workspace disponibili e mostra quello corrente
tfw() {
    tf_log "Workspace disponibili:"
    terraform workspace list
    echo
    local current=$(get_current_workspace)
    if [ -n "$current" ]; then
        tf_log "Workspace corrente: $current"
    else
        tf_warn "Nessun workspace selezionato"
    fi
}

# Seleziona workspace
tfws() {
    local workspace="$1"

    if [ -z "$workspace" ]; then
        tf_error "Workspace richiesto. Uso: tfws <workspace>"
        return 1
    fi

    tf_log "Selezione workspace: $workspace"
    if terraform workspace select "$workspace" 2>/dev/null; then
        tf_success "Workspace selezionato: $workspace"
    else
        tf_warn "Workspace $workspace non esiste, lo creo..."
        terraform workspace new "$workspace"
    fi
}

# Funzione di help
tfh() {
    echo -e "${BLUE}Terraform Wrapper Functions${NC}"
    echo
    echo "Queste funzioni automatizzano la sincronizzazione dei tfvars usando il workspace corrente."
    echo
    echo -e "${GREEN}Funzioni disponibili:${NC}"
    echo -e "  ${YELLOW}tfi${NC} [args...]               - terraform init senza sync"
    echo -e "  ${YELLOW}tfp${NC} [args...]               - terraform plan con tfvars automatico"
    echo -e "  ${YELLOW}tfa${NC} [args...]               - terraform apply con tfvars automatico"
    echo -e "  ${YELLOW}tfd${NC} [args...]               - terraform destroy con tfvars automatico"
    echo -e "  ${YELLOW}tfw${NC}                         - mostra workspace disponibili e corrente"
    echo -e "  ${YELLOW}tfws${NC} <workspace>            - seleziona/crea workspace"
    echo -e "  ${YELLOW}tfh${NC}                         - mostra questo aiuto"
    echo
    echo -e "${GREEN}Esempi:${NC}"
    echo "  tfws smartflow-dev                   # Seleziona workspace"
    echo "  tfi                                  # Init"
    echo "  tfp                                  # Plan per workspace corrente"
    echo "  tfa                                  # Apply per workspace corrente"
    echo "  tfa -auto-approve                    # Apply automatico"
    echo "  tfd                                  # Destroy per workspace corrente"
    echo
    echo -e "${GREEN}Workflow automatico:${NC}"
    echo "  1. Rileva workspace corrente (terraform workspace show)"
    echo "  2. Sincronizza tfvars/<workspace>.tfvars da S3"
    echo "  3. Esegue comando terraform con file tfvars appropriato"
    echo "  4. (Per apply) Opzione di push tfvars aggiornato su S3"
    echo
    echo -e "${BLUE}Configurazione:${NC}"
    echo "  File tfvars: tfvars/<workspace>.tfvars"
    echo "  Script init: scripts/init"
    echo
    echo -e "${YELLOW}Nota:${NC} Seleziona un workspace con 'tfws <workspace>' prima di usare tfp/tfa/tfd."
}

# Messaggio di inizializzazione
tf_success "Terraform wrapper functions caricati"
echo "Usa 'tfh' per vedere l'aiuto completo"
echo "Workspace corrente: $(get_current_workspace 2>/dev/null || echo 'nessuno')"