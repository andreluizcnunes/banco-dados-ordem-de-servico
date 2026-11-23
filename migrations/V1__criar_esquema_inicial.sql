CREATE FUNCTION atualizar_coluna_atualizado_em()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.atualizado_em = now();
    RETURN NEW;
END;
$$;

CREATE TABLE usuarios (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    nome VARCHAR(150) NOT NULL,
    email VARCHAR(254) NOT NULL,
    senha_hash VARCHAR(255) NOT NULL,
    perfil VARCHAR(20) NOT NULL,
    ativo BOOLEAN NOT NULL DEFAULT TRUE,
    criado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
    atualizado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT usuarios_pk PRIMARY KEY (id),
    CONSTRAINT usuarios_id_perfil_unico UNIQUE (id, perfil),
    CONSTRAINT usuarios_perfil_valido CHECK (perfil IN ('DONO', 'ADMINISTRATIVO', 'TECNICO')),
    CONSTRAINT usuarios_nome_preenchido CHECK (btrim(nome) <> ''),
    CONSTRAINT usuarios_email_preenchido CHECK (btrim(email) <> '')
);

CREATE UNIQUE INDEX usuarios_email_unico ON usuarios (lower(email));

CREATE TRIGGER usuarios_atualizado_em
    BEFORE UPDATE ON usuarios
    FOR EACH ROW EXECUTE FUNCTION atualizar_coluna_atualizado_em();

CREATE TABLE clientes (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    nome VARCHAR(200) NOT NULL,
    contato VARCHAR(150),
    telefone VARCHAR(30),
    email VARCHAR(254),
    endereco VARCHAR(300),
    criado_por BIGINT NOT NULL,
    criado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
    atualizado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT clientes_pk PRIMARY KEY (id),
    CONSTRAINT clientes_criado_por_fk FOREIGN KEY (criado_por) REFERENCES usuarios (id),
    CONSTRAINT clientes_nome_preenchido CHECK (btrim(nome) <> '')
);

CREATE INDEX clientes_nome_idx ON clientes (lower(nome));

CREATE TRIGGER clientes_atualizado_em
    BEFORE UPDATE ON clientes
    FOR EACH ROW EXECUTE FUNCTION atualizar_coluna_atualizado_em();

CREATE TABLE ordens_servico (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    cliente_id BIGINT NOT NULL,
    data_abertura TIMESTAMPTZ NOT NULL DEFAULT now(),
    descricao TEXT NOT NULL,
    endereco_atendimento VARCHAR(300) NOT NULL,
    contato_atendimento VARCHAR(150),
    telefone_atendimento VARCHAR(30),
    email_atendimento VARCHAR(254),
    status_atendimento VARCHAR(20) NOT NULL DEFAULT 'ABERTA',
    motivo_aguardando TEXT,
    data_inicio_atendimento TIMESTAMPTZ,
    data_conclusao TIMESTAMPTZ,
    concluida_por BIGINT,
    criado_por BIGINT NOT NULL,
    criado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
    atualizado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ordens_servico_pk PRIMARY KEY (id),
    CONSTRAINT ordens_servico_id_status_unico UNIQUE (id, status_atendimento),
    CONSTRAINT ordens_servico_cliente_fk FOREIGN KEY (cliente_id) REFERENCES clientes (id),
    CONSTRAINT ordens_servico_concluida_por_fk FOREIGN KEY (concluida_por) REFERENCES usuarios (id),
    CONSTRAINT ordens_servico_criado_por_fk FOREIGN KEY (criado_por) REFERENCES usuarios (id),
    CONSTRAINT ordens_servico_status_valido CHECK (
        status_atendimento IN ('ABERTA', 'EM_ATENDIMENTO', 'AGUARDANDO', 'CONCLUIDA')
    ),
    CONSTRAINT ordens_servico_descricao_preenchida CHECK (btrim(descricao) <> ''),
    CONSTRAINT ordens_servico_endereco_preenchido CHECK (btrim(endereco_atendimento) <> ''),
    CONSTRAINT ordens_servico_motivo_aguardando CHECK (
        (status_atendimento = 'AGUARDANDO') = (motivo_aguardando IS NOT NULL AND btrim(motivo_aguardando) <> '')
    ),
    CONSTRAINT ordens_servico_conclusao_consistente CHECK (
        (status_atendimento = 'CONCLUIDA') = (data_conclusao IS NOT NULL AND concluida_por IS NOT NULL)
    ),
    CONSTRAINT ordens_servico_datas_coerentes CHECK (
        (data_inicio_atendimento IS NULL OR data_inicio_atendimento >= data_abertura)
        AND (data_conclusao IS NULL OR data_conclusao >= data_abertura)
    )
);

CREATE INDEX ordens_servico_cliente_idx ON ordens_servico (cliente_id, data_abertura DESC);
CREATE INDEX ordens_servico_status_data_idx ON ordens_servico (status_atendimento, data_abertura DESC);
CREATE INDEX ordens_servico_data_abertura_idx ON ordens_servico (data_abertura DESC);

CREATE TRIGGER ordens_servico_atualizado_em
    BEFORE UPDATE ON ordens_servico
    FOR EACH ROW EXECUTE FUNCTION atualizar_coluna_atualizado_em();

CREATE TABLE ordens_servico_tecnicos (
    ordem_servico_id BIGINT NOT NULL,
    tecnico_id BIGINT NOT NULL,
    tecnico_perfil VARCHAR(20) NOT NULL DEFAULT 'TECNICO',
    atribuido_por BIGINT NOT NULL,
    atribuido_em TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ordens_servico_tecnicos_pk PRIMARY KEY (ordem_servico_id, tecnico_id),
    CONSTRAINT ordens_servico_tecnicos_os_fk FOREIGN KEY (ordem_servico_id) REFERENCES ordens_servico (id),
    CONSTRAINT ordens_servico_tecnicos_tecnico_fk FOREIGN KEY (tecnico_id, tecnico_perfil)
        REFERENCES usuarios (id, perfil),
    CONSTRAINT ordens_servico_tecnicos_atribuido_por_fk FOREIGN KEY (atribuido_por) REFERENCES usuarios (id),
    CONSTRAINT ordens_servico_tecnicos_somente_tecnico CHECK (tecnico_perfil = 'TECNICO')
);

CREATE INDEX ordens_servico_tecnicos_tecnico_idx ON ordens_servico_tecnicos (tecnico_id);

CREATE TABLE registros_atendimento (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    ordem_servico_id BIGINT NOT NULL,
    autor_id BIGINT NOT NULL,
    tipo VARCHAR(20) NOT NULL DEFAULT 'ATIVIDADE',
    descricao TEXT NOT NULL,
    materiais_utilizados TEXT,
    registrado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT registros_atendimento_pk PRIMARY KEY (id),
    CONSTRAINT registros_atendimento_os_fk FOREIGN KEY (ordem_servico_id) REFERENCES ordens_servico (id),
    CONSTRAINT registros_atendimento_autor_fk FOREIGN KEY (autor_id) REFERENCES usuarios (id),
    CONSTRAINT registros_atendimento_tipo_valido CHECK (tipo IN ('ATIVIDADE', 'IMPEDIMENTO')),
    CONSTRAINT registros_atendimento_descricao_preenchida CHECK (btrim(descricao) <> '')
);

CREATE INDEX registros_atendimento_os_idx ON registros_atendimento (ordem_servico_id, registrado_em);

CREATE TABLE itens_ordem_servico (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    ordem_servico_id BIGINT NOT NULL,
    tipo VARCHAR(20) NOT NULL,
    descricao VARCHAR(500) NOT NULL,
    local_realizacao VARCHAR(300),
    quantidade NUMERIC(12, 3) NOT NULL,
    preco_unitario NUMERIC(12, 2) NOT NULL,
    valor_total NUMERIC(14, 2) GENERATED ALWAYS AS (round(quantidade * preco_unitario, 2)) STORED,
    criado_por BIGINT NOT NULL,
    criado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
    atualizado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT itens_ordem_servico_pk PRIMARY KEY (id),
    CONSTRAINT itens_ordem_servico_os_fk FOREIGN KEY (ordem_servico_id) REFERENCES ordens_servico (id),
    CONSTRAINT itens_ordem_servico_criado_por_fk FOREIGN KEY (criado_por) REFERENCES usuarios (id),
    CONSTRAINT itens_ordem_servico_tipo_valido CHECK (tipo IN ('PRODUTO', 'SERVICO', 'MAO_DE_OBRA')),
    CONSTRAINT itens_ordem_servico_descricao_preenchida CHECK (btrim(descricao) <> ''),
    CONSTRAINT itens_ordem_servico_quantidade_positiva CHECK (quantidade > 0),
    CONSTRAINT itens_ordem_servico_preco_nao_negativo CHECK (preco_unitario >= 0)
);

CREATE INDEX itens_ordem_servico_os_idx ON itens_ordem_servico (ordem_servico_id);

CREATE TRIGGER itens_ordem_servico_atualizado_em
    BEFORE UPDATE ON itens_ordem_servico
    FOR EACH ROW EXECUTE FUNCTION atualizar_coluna_atualizado_em();

CREATE TABLE cobrancas (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    ordem_servico_id BIGINT NOT NULL,
    ordem_servico_status VARCHAR(20) NOT NULL DEFAULT 'CONCLUIDA',
    valor_total NUMERIC(14, 2) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDENTE',
    data_vencimento DATE,
    enviada_por BIGINT NOT NULL,
    enviada_em TIMESTAMPTZ NOT NULL DEFAULT now(),
    atualizado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT cobrancas_pk PRIMARY KEY (id),
    CONSTRAINT cobrancas_os_unica UNIQUE (ordem_servico_id),
    CONSTRAINT cobrancas_id_status_unico UNIQUE (id, status),
    CONSTRAINT cobrancas_os_concluida_fk FOREIGN KEY (ordem_servico_id, ordem_servico_status)
        REFERENCES ordens_servico (id, status_atendimento),
    CONSTRAINT cobrancas_enviada_por_fk FOREIGN KEY (enviada_por) REFERENCES usuarios (id),
    CONSTRAINT cobrancas_somente_os_concluida CHECK (ordem_servico_status = 'CONCLUIDA'),
    CONSTRAINT cobrancas_status_valido CHECK (status IN ('PENDENTE', 'PAGA')),
    CONSTRAINT cobrancas_valor_nao_negativo CHECK (valor_total >= 0)
);

CREATE INDEX cobrancas_status_vencimento_idx ON cobrancas (status, data_vencimento);

CREATE TRIGGER cobrancas_atualizado_em
    BEFORE UPDATE ON cobrancas
    FOR EACH ROW EXECUTE FUNCTION atualizar_coluna_atualizado_em();

CREATE TABLE pagamentos (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    cobranca_id BIGINT NOT NULL,
    cobranca_status VARCHAR(20) NOT NULL DEFAULT 'PAGA',
    valor_recebido NUMERIC(14, 2) NOT NULL,
    data_pagamento DATE NOT NULL,
    registrado_por BIGINT NOT NULL,
    registrado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pagamentos_pk PRIMARY KEY (id),
    CONSTRAINT pagamentos_cobranca_unica UNIQUE (cobranca_id),
    CONSTRAINT pagamentos_id_valor_unico UNIQUE (id, valor_recebido),
    CONSTRAINT pagamentos_cobranca_paga_fk FOREIGN KEY (cobranca_id, cobranca_status)
        REFERENCES cobrancas (id, status),
    CONSTRAINT pagamentos_registrado_por_fk FOREIGN KEY (registrado_por) REFERENCES usuarios (id),
    CONSTRAINT pagamentos_somente_cobranca_paga CHECK (cobranca_status = 'PAGA'),
    CONSTRAINT pagamentos_valor_positivo CHECK (valor_recebido > 0)
);

CREATE TABLE lancamentos_caixa (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    pagamento_id BIGINT NOT NULL,
    valor NUMERIC(14, 2) NOT NULL,
    data_lancamento DATE NOT NULL,
    criado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT lancamentos_caixa_pk PRIMARY KEY (id),
    CONSTRAINT lancamentos_caixa_pagamento_unico UNIQUE (pagamento_id),
    CONSTRAINT lancamentos_caixa_pagamento_fk FOREIGN KEY (pagamento_id, valor)
        REFERENCES pagamentos (id, valor_recebido),
    CONSTRAINT lancamentos_caixa_valor_positivo CHECK (valor > 0)
);

CREATE INDEX lancamentos_caixa_data_idx ON lancamentos_caixa (data_lancamento);
