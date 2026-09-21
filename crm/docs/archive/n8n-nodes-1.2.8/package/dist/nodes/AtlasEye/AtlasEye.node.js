"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.AtlasEye = void 0;
class AtlasEye {
    constructor() {
        this.description = {
            displayName: 'Atlas Eye',
            name: 'atlasEye',
            icon: 'file:atlas-eye.png',
            group: ['transform'],
            version: 1,
            subtitle: '={{$parameter["operation"] + ": " + $parameter["resource"]}}',
            description: 'Interact with the Atlas Eye CRM API',
            defaults: {
                name: 'Atlas Eye',
            },
            inputs: ['main'],
            outputs: ['main'],
            credentials: [
                {
                    name: 'atlasEyeApi',
                    required: true,
                },
            ],
            requestDefaults: {
                baseURL: '={{$credentials.baseUrl}}',
                headers: {
                    Accept: 'application/json',
                    'Content-Type': 'application/json',
                },
            },
            properties: [
                // ──────────── Resource selector ────────────
                {
                    displayName: 'Resource',
                    name: 'resource',
                    type: 'options',
                    noDataExpression: true,
                    options: [
                        { name: 'Lead', value: 'lead' },
                        { name: 'Pipeline', value: 'pipeline' },
                        { name: 'User', value: 'user' },
                        { name: 'Notification', value: 'notification' },
                    ],
                    default: 'lead',
                },
                // ═══════════════════════════════════════════
                //               LEAD
                // ═══════════════════════════════════════════
                {
                    displayName: 'Operation',
                    name: 'operation',
                    type: 'options',
                    noDataExpression: true,
                    displayOptions: { show: { resource: ['lead'] } },
                    options: [
                        { name: 'Create', value: 'create', description: 'Create a new lead', action: 'Create a lead', routing: { request: { method: 'POST', url: '/api/leads' } } },
                        { name: 'List', value: 'list', description: 'List all leads', action: 'List leads', routing: { request: { method: 'GET', url: '/api/leads' } } },
                        { name: 'Update', value: 'update', description: 'Update a lead', action: 'Update a lead', routing: { request: { method: 'PATCH', url: '=/api/leads/{{$parameter["leadId"]}}' } } },
                        { name: 'Send Message', value: 'sendMessage', description: 'Send a message to a lead chat', action: 'Send a message', routing: { request: { method: 'POST', url: '=/api/leads/{{$parameter["leadId"]}}/messages' } } },
                        { name: 'Add History Event', value: 'addEvent', description: 'Add a history event to a lead', action: 'Add a history event', routing: { request: { method: 'POST', url: '=/api/leads/{{$parameter["leadId"]}}/history' } } },
                        { name: 'Edit History Event', value: 'editEvent', description: 'Edit a history event', action: 'Edit a history event', routing: { request: { method: 'PATCH', url: '=/api/leads/history/{{$parameter["eventId"]}}' } } },
                        { name: 'Delete History Event', value: 'deleteEvent', description: 'Delete a history event', action: 'Delete a history event', routing: { request: { method: 'DELETE', url: '=/api/leads/history/{{$parameter["eventId"]}}' } } },
                    ],
                    default: 'list',
                },
                // Lead — List filters
                {
                    displayName: 'Return All',
                    name: 'returnAll',
                    type: 'boolean',
                    default: false,
                    description: 'Whether to return all results or only up to a given limit',
                    displayOptions: { show: { resource: ['lead'], operation: ['list'] } },
                    routing: { send: { type: 'query', property: 'returnAll' } },
                },
                {
                    displayName: 'Limit',
                    name: 'limit',
                    type: 'number',
                    default: 20,
                    description: 'Max number of results to return (max 100)',
                    typeOptions: { minValue: 1, maxValue: 100 },
                    displayOptions: { show: { resource: ['lead'], operation: ['list'], returnAll: [false] } },
                    routing: { send: { type: 'query', property: 'limit' } },
                },
                {
                    displayName: 'Page',
                    name: 'page',
                    type: 'number',
                    default: 1,
                    description: 'Page number for pagination',
                    typeOptions: { minValue: 1 },
                    displayOptions: { show: { resource: ['lead'], operation: ['list'] } },
                    routing: { send: { type: 'query', property: 'page' } },
                },
                {
                    displayName: 'Additional Filters',
                    name: 'filters',
                    type: 'collection',
                    placeholder: 'Add Filter',
                    default: {},
                    displayOptions: { show: { resource: ['lead'], operation: ['list'] } },
                    options: [
                        {
                            displayName: 'Search Query',
                            name: 'q',
                            type: 'string',
                            default: '',
                            description: 'Search by name, email, or phone',
                            routing: { send: { type: 'query', property: 'q' } },
                        },
                        {
                            displayName: 'Phone',
                            name: 'phone',
                            type: 'string',
                            default: '',
                            description: 'Filter by phone number',
                            routing: { send: { type: 'query', property: 'phone' } },
                        },
                        {
                            displayName: 'Assigned To (Member ID)',
                            name: 'assigned_to',
                            type: 'options',
                            typeOptions: { loadOptionsMethod: 'getMembers' },
                            default: '',
                            description: 'Filter by assigned member',
                            routing: { send: { type: 'query', property: 'assigned_to' } },
                        },
                        {
                            displayName: 'Status Name or ID',
                            name: 'status',
                            type: 'options',
                            typeOptions: { loadOptionsMethod: 'getStages', loadOptionsDependsOn: ['pipeline_id'] },
                            default: '',
                            description: 'Filter by stage name or ID. Choose from the list, or specify an ID using an expression. Requires a Pipeline to be selected.',
                            routing: { send: { type: 'query', property: 'status' } },
                        },
                        {
                            displayName: 'Tags',
                            name: 'tags',
                            type: 'multiOptions',
                            typeOptions: { loadOptionsMethod: 'getTags' },
                            default: [],
                            description: 'Filter by tags',
                            routing: { send: { type: 'query', property: 'tags' } },
                        },
                        {
                            displayName: 'Pipeline Name or ID',
                            name: 'pipeline_id',
                            type: 'options',
                            typeOptions: { loadOptionsMethod: 'getPipelines' },
                            default: '',
                            description: 'Filter by pipeline ID. Choose from the list, or specify an ID using an expression.',
                            routing: { send: { type: 'query', property: 'pipeline_id' } },
                        },
                        {
                            displayName: 'Custom Field',
                            name: 'cf_id',
                            type: 'options',
                            typeOptions: { loadOptionsMethod: 'getCustomFields' },
                            default: '',
                            description: 'Filter by a specific custom field',
                            routing: { send: { type: 'query', property: 'cf_id' } },
                        },
                        {
                            displayName: 'Custom Field Value',
                            name: 'cf_value',
                            type: 'string',
                            default: '',
                            description: 'The value to match for the selected custom field',
                            displayOptions: {
                                hide: {
                                    cf_id: [''],
                                },
                            },
                            routing: { send: { type: 'query', property: 'cf_value' } },
                        },
                    ],
                },
                // Lead — Create
                {
                    displayName: 'Name',
                    name: 'name',
                    type: 'string',
                    default: '',
                    required: true,
                    description: 'Name of the lead',
                    displayOptions: { show: { resource: ['lead'], operation: ['create'] } },
                    routing: { send: { type: 'body', property: 'name' } },
                },
                {
                    displayName: 'Source',
                    name: 'source',
                    type: 'options',
                    options: [
                        { name: 'AI Agent', value: 'ai_agent' },
                        { name: 'Human', value: 'human' },
                        { name: 'System', value: 'system' },
                    ],
                    default: 'ai_agent',
                    required: true,
                    description: 'Source of this action',
                    displayOptions: { show: { resource: ['lead'], operation: ['create'] } },
                    routing: { send: { type: 'body', property: 'source' } },
                },
                {
                    displayName: 'Additional Fields',
                    name: 'additionalFields',
                    type: 'collection',
                    placeholder: 'Add Field',
                    default: {},
                    displayOptions: { show: { resource: ['lead'], operation: ['create'] } },
                    options: [
                        {
                            displayName: 'Email',
                            name: 'email',
                            type: 'string',
                            default: '',
                            placeholder: 'email@example.com',
                            routing: { send: { type: 'body', property: 'email' } },
                        },
                        {
                            displayName: 'Phone',
                            name: 'phone',
                            type: 'string',
                            default: '',
                            placeholder: '+55 11 91234-5678',
                            routing: { send: { type: 'body', property: 'phone' } },
                        },
                        {
                            displayName: 'Pipeline ID',
                            name: 'pipeline_id',
                            type: 'string',
                            default: '',
                            description: 'Place lead in first stage of this pipeline',
                            routing: { send: { type: 'body', property: 'pipeline_id' } },
                        },
                        {
                            displayName: 'Assigned To',
                            name: 'assigned_to',
                            type: 'options',
                            typeOptions: { loadOptionsMethod: 'getMembers' },
                            default: '',
                            description: 'Member responsible for the lead. Choose from the list, or specify an ID using an <a href="https://docs.n8n.io/code-examples/expressions/">expression</a>.',
                            routing: { send: { type: 'body', property: 'assigned_to' } },
                        },
                        {
                            displayName: 'Status',
                            name: 'status',
                            type: 'string',
                            default: '',
                            description: 'Initial status (e.g. open)',
                            routing: { send: { type: 'body', property: 'status' } },
                        },
                        {
                            displayName: 'Tags',
                            name: 'tags',
                            type: 'multiOptions',
                            typeOptions: { loadOptionsMethod: 'getTags' },
                            default: [],
                            description: 'List of tags to associate. Choose from the list, or specify IDs using an <a href="https://docs.n8n.io/code-examples/expressions/">expression</a>.',
                            routing: {
                                send: {
                                    type: 'body',
                                    property: 'tags',
                                },
                            },
                        },
                    ],
                },
                // Lead — Update
                {
                    displayName: 'Lead ID or Phone',
                    name: 'leadId',
                    type: 'string',
                    default: '',
                    required: true,
                    description: 'ID or phone number of the lead. If a phone number is used and the lead doesn\'t exist, it will be created automatically.',
                    displayOptions: { show: { resource: ['lead'], operation: ['update', 'sendMessage', 'addEvent'] } },
                },
                {
                    displayName: 'Source',
                    name: 'source',
                    type: 'options',
                    options: [
                        { name: 'AI Agent', value: 'ai_agent' },
                        { name: 'Human', value: 'human' },
                        { name: 'System', value: 'system' },
                    ],
                    default: 'ai_agent',
                    required: true,
                    description: 'Source of this action',
                    displayOptions: { show: { resource: ['lead'], operation: ['update'] } },
                    routing: { send: { type: 'body', property: 'source' } },
                },
                {
                    displayName: 'Pipeline Name or ID',
                    name: 'pipeline_id',
                    type: 'options',
                    typeOptions: { loadOptionsMethod: 'getPipelines' },
                    default: '',
                    description: 'Move lead to this pipeline. Choose from the list, or specify an ID using an <a href="https://docs.n8n.io/code-examples/expressions/">expression</a>. Leave empty to keep unchanged.',
                    displayOptions: { show: { resource: ['lead'], operation: ['update'] } },
                    routing: { send: { type: 'body', property: 'pipeline_id' } },
                },
                {
                    displayName: 'Stage Name or ID',
                    name: 'stage_id',
                    type: 'options',
                    typeOptions: { loadOptionsMethod: 'getStages', loadOptionsDependsOn: ['pipeline_id'] },
                    default: '',
                    description: 'Move lead to this stage. Choose from the list, or specify an ID using an <a href="https://docs.n8n.io/code-examples/expressions/">expression</a>. Leave empty to keep unchanged.',
                    displayOptions: { show: { resource: ['lead'], operation: ['update'] } },
                    routing: { send: { type: 'body', property: 'stage_id' } },
                },
                {
                    displayName: 'Custom Fields',
                    name: 'customFieldsList',
                    type: 'fixedCollection',
                    placeholder: 'Add Custom Field',
                    typeOptions: { multipleValues: true },
                    default: {},
                    displayOptions: { show: { resource: ['lead'], operation: ['update'] } },
                    description: 'Add custom field values from your Atlas Eye account',
                    options: [
                        {
                            displayName: 'Field',
                            name: 'field',
                            values: [
                                {
                                    displayName: 'Field Name',
                                    name: 'fieldId',
                                    type: 'options',
                                    typeOptions: { loadOptionsMethod: 'getAllCustomFields' },
                                    default: '',
                                    description: 'Choose the custom field to update',
                                },
                                {
                                    displayName: 'Value',
                                    name: 'value',
                                    type: 'options',
                                    typeOptions: {
                                        loadOptionsMethod: 'getAllCustomFieldValues',
                                        loadOptionsDependsOn: ['fieldId'],
                                    },
                                    default: '',
                                    description: 'Select a value from the available options. For text/date/datetime fields, switch to Expression mode and type the value directly (ISO 8601 for dates, e.g. 2024-12-31T23:59:59Z).',
                                },
                            ],
                        },
                    ],
                    routing: {
                        send: {
                            type: 'body',
                            property: 'custom_fields',
                            value: '={{ $value.field.reduce((acc, curr) => { if (curr.fieldId) acc[curr.fieldId] = curr.value; return acc; }, {}) }}',
                        },
                    },
                },
                {
                    displayName: 'Embedded',
                    name: 'updateFields',
                    type: 'collection',
                    placeholder: 'Add custom embedded',
                    default: {},
                    displayOptions: { show: { resource: ['lead'], operation: ['update'] } },
                    options: [
                        {
                            displayName: 'Name',
                            name: 'name',
                            type: 'string',
                            default: '',
                            routing: { send: { type: 'body', property: 'name' } },
                        },
                        {
                            displayName: 'Email',
                            name: 'email',
                            type: 'string',
                            default: '',
                            routing: { send: { type: 'body', property: 'email' } },
                        },
                        {
                            displayName: 'Phone',
                            name: 'phone',
                            type: 'string',
                            default: '',
                            routing: { send: { type: 'body', property: 'phone' } },
                        },
                        {
                            displayName: 'Assigned To',
                            name: 'assigned_to',
                            type: 'options',
                            typeOptions: { loadOptionsMethod: 'getMembers' },
                            default: '',
                            description: 'Member responsible for the lead. Choose from the list, or specify an ID using an <a href="https://docs.n8n.io/code-examples/expressions/">expression</a>.',
                            routing: { send: { type: 'body', property: 'assigned_to' } },
                        },
                        {
                            displayName: 'Tags',
                            name: 'tags',
                            type: 'multiOptions',
                            typeOptions: { loadOptionsMethod: 'getTags' },
                            default: [],
                            description: 'Replaces all current tags with this list. Choose from the list, or specify IDs using an <a href="https://docs.n8n.io/code-examples/expressions/">expression</a>.',
                            routing: {
                                send: {
                                    type: 'body',
                                    property: 'tags',
                                },
                            },
                        },
                    ],
                },
                {
                    displayName: 'Content',
                    name: 'content',
                    type: 'string',
                    default: '',
                    required: true,
                    description: 'Message content',
                    typeOptions: { rows: 4 },
                    displayOptions: { show: { resource: ['lead'], operation: ['sendMessage'] } },
                    routing: { send: { type: 'body', property: 'content' } },
                },
                {
                    displayName: 'Message Type',
                    name: 'type',
                    type: 'options',
                    options: [
                        { name: 'WhatsApp', value: 'whatsapp' },
                    ],
                    default: 'whatsapp',
                    required: true,
                    displayOptions: { show: { resource: ['lead'], operation: ['sendMessage'] } },
                    routing: { send: { type: 'body', property: 'type' } },
                },
                {
                    displayName: 'Source',
                    name: 'source',
                    type: 'options',
                    options: [
                        { name: 'AI Agent', value: 'ai_agent' },
                        { name: 'Human', value: 'human' },
                    ],
                    default: 'ai_agent',
                    required: true,
                    displayOptions: { show: { resource: ['lead'], operation: ['sendMessage'] } },
                    routing: { send: { type: 'body', property: 'source' } },
                },
                {
                    displayName: 'Additional Fields',
                    name: 'additionalFields',
                    type: 'collection',
                    placeholder: 'Add Field',
                    default: {},
                    displayOptions: { show: { resource: ['lead'], operation: ['sendMessage'] } },
                    options: [
                        {
                            displayName: 'Direction',
                            name: 'direction',
                            type: 'options',
                            options: [
                                { name: 'Outbound', value: 'outbound' },
                                { name: 'Inbound', value: 'inbound' },
                            ],
                            default: 'outbound',
                            routing: { send: { type: 'body', property: 'direction' } },
                        },
                        {
                            displayName: 'Sender Name',
                            name: 'sender_name',
                            type: 'string',
                            default: '',
                            routing: { send: { type: 'body', property: 'sender_name' } },
                        },
                        {
                            displayName: 'Media URL',
                            name: 'media_url',
                            type: 'string',
                            default: '',
                            routing: { send: { type: 'body', property: 'media_url' } },
                        },
                        {
                            displayName: 'Media Type',
                            name: 'media_type',
                            type: 'options',
                            options: [
                                { name: 'Image', value: 'image' },
                                { name: 'Video', value: 'video' },
                                { name: 'Audio', value: 'audio' },
                                { name: 'Document', value: 'document' },
                                { name: 'Sticker', value: 'sticker' },
                            ],
                            default: 'image',
                            description: 'Type of media file attached',
                            routing: { send: { type: 'body', property: 'media_type' } },
                        },
                        {
                            displayName: 'Reply To Message ID',
                            name: 'reply_to_message_id',
                            type: 'string',
                            default: '',
                            description: 'ID of the original message for quote replies',
                            routing: { send: { type: 'body', property: 'reply_to_message_id' } },
                        },
                    ],
                },
                {
                    displayName: 'Event ID',
                    name: 'eventId',
                    type: 'string',
                    default: '',
                    required: true,
                    description: 'ID of the history event',
                    displayOptions: { show: { resource: ['lead'], operation: ['editEvent', 'deleteEvent'] } },
                },
                {
                    displayName: 'Content',
                    name: 'content',
                    type: 'string',
                    default: '',
                    required: true,
                    description: 'Event description',
                    typeOptions: { rows: 3 },
                    displayOptions: { show: { resource: ['lead'], operation: ['addEvent'] } },
                    routing: { send: { type: 'body', property: 'content' } },
                },
                {
                    displayName: 'Event Type',
                    name: 'type',
                    type: 'options',
                    options: [
                        { name: 'Note', value: 'note' },
                        { name: 'Call', value: 'call' },
                        { name: 'Email', value: 'email' },
                        { name: 'System', value: 'system' },
                        { name: 'WhatsApp', value: 'whatsapp' },
                    ],
                    default: 'note',
                    required: true,
                    description: 'Type of the history event',
                    displayOptions: { show: { resource: ['lead'], operation: ['addEvent'] } },
                    routing: { send: { type: 'body', property: 'type' } },
                },
                {
                    displayName: 'Source',
                    name: 'source',
                    type: 'options',
                    options: [
                        { name: 'AI Agent', value: 'ai_agent' },
                        { name: 'Human', value: 'human' },
                        { name: 'System', value: 'system' },
                    ],
                    default: 'ai_agent',
                    required: true,
                    displayOptions: { show: { resource: ['lead'], operation: ['addEvent', 'editEvent', 'deleteEvent'] } },
                    routing: { send: { type: 'body', property: 'source' } },
                },
                {
                    displayName: 'Additional Fields',
                    name: 'additionalFields',
                    type: 'collection',
                    placeholder: 'Add Field',
                    default: {},
                    displayOptions: { show: { resource: ['lead'], operation: ['addEvent', 'editEvent'] } },
                    options: [
                        {
                            displayName: 'Content',
                            name: 'content',
                            type: 'string',
                            default: '',
                            description: 'New event description (for Edit Event)',
                            typeOptions: { rows: 3 },
                            displayOptions: { show: { '/operation': ['editEvent'] } },
                            routing: { send: { type: 'body', property: 'content' } },
                        },
                        {
                            displayName: 'Metadata',
                            name: 'metadata',
                            type: 'json',
                            default: '{}',
                            description: 'JSON object with additional metadata for the event',
                            routing: { send: { type: 'body', property: 'metadata' } },
                        },
                    ],
                },
                // ═══════════════════════════════════════════
                //            PIPELINE
                // ═══════════════════════════════════════════
                {
                    displayName: 'Operation',
                    name: 'operation',
                    type: 'options',
                    noDataExpression: true,
                    displayOptions: { show: { resource: ['pipeline'] } },
                    options: [
                        { name: 'Create', value: 'create', description: 'Create a pipeline', action: 'Create a pipeline', routing: { request: { method: 'POST', url: '/api/pipelines' } } },
                        { name: 'Delete', value: 'delete', description: 'Delete a pipeline', action: 'Delete a pipeline', routing: { request: { method: 'DELETE', url: '=/api/pipelines/{{$parameter["pipelineId"]}}' } } },
                        { name: 'Get', value: 'get', description: 'Get a pipeline', action: 'Get a pipeline', routing: { request: { method: 'GET', url: '=/api/pipelines/{{$parameter["pipelineId"]}}' } } },
                        { name: 'List', value: 'list', description: 'List all pipelines', action: 'List pipelines', routing: { request: { method: 'GET', url: '/api/pipelines' } } },
                        { name: 'Update', value: 'update', description: 'Update a pipeline', action: 'Update a pipeline', routing: { request: { method: 'PATCH', url: '=/api/pipelines/{{$parameter["pipelineId"]}}' } } },
                        { name: 'Create Stage', value: 'createStage', description: 'Create a stage in a pipeline', action: 'Create a stage', routing: { request: { method: 'POST', url: '=/api/pipelines/{{$parameter["pipelineId"]}}/stages' } } },
                        { name: 'Delete Stage', value: 'deleteStage', description: 'Delete a stage', action: 'Delete a stage', routing: { request: { method: 'DELETE', url: '=/api/pipelines/stages/{{$parameter["stageId"]}}' } } },
                        { name: 'Get Stage', value: 'getStage', description: 'Get a stage by ID', action: 'Get a stage', routing: { request: { method: 'GET', url: '=/api/pipelines/stages/{{$parameter["stageId"]}}' } } },
                        { name: 'List Stages', value: 'listStages', description: 'List stages of a pipeline', action: 'List stages', routing: { request: { method: 'GET', url: '=/api/pipelines/{{$parameter["pipelineId"]}}/stages' } } },
                        { name: 'List Stage Colors', value: 'listColors', description: 'List available stage colors', action: 'List stage colors', routing: { request: { method: 'GET', url: '/api/pipelines/stage-colors' } } },
                        { name: 'Update Stage', value: 'updateStage', description: 'Update a stage', action: 'Update a stage', routing: { request: { method: 'PATCH', url: '=/api/pipelines/stages/{{$parameter["stageId"]}}' } } },
                    ],
                    default: 'list',
                },
                // Pipeline — ID (for Get, Update, Delete)
                {
                    displayName: 'Pipeline ID',
                    name: 'pipelineId',
                    type: 'string',
                    default: '',
                    required: true,
                    displayOptions: { show: { resource: ['pipeline'], operation: ['get', 'update', 'delete', 'createStage', 'listStages'] } },
                },
                // Pipeline — Create
                {
                    displayName: 'Name',
                    name: 'name',
                    type: 'string',
                    default: '',
                    required: true,
                    displayOptions: { show: { resource: ['pipeline'], operation: ['create'] } },
                    routing: { send: { type: 'body', property: 'name' } },
                },
                {
                    displayName: 'Source',
                    name: 'source',
                    type: 'options',
                    options: [
                        { name: 'AI Agent', value: 'ai_agent' },
                        { name: 'Human', value: 'human' },
                        { name: 'System', value: 'system' },
                    ],
                    default: 'ai_agent',
                    required: true,
                    displayOptions: { show: { resource: ['pipeline'], operation: ['create'] } },
                    routing: { send: { type: 'body', property: 'source' } },
                },
                // Pipeline — Update
                {
                    displayName: 'Source',
                    name: 'source',
                    type: 'options',
                    options: [
                        { name: 'AI Agent', value: 'ai_agent' },
                        { name: 'Human', value: 'human' },
                        { name: 'System', value: 'system' },
                    ],
                    default: 'ai_agent',
                    required: true,
                    displayOptions: { show: { resource: ['pipeline'], operation: ['update'] } },
                    routing: { send: { type: 'body', property: 'source' } },
                },
                {
                    displayName: 'Update Fields',
                    name: 'updateFields',
                    type: 'collection',
                    placeholder: 'Add Field',
                    default: {},
                    displayOptions: { show: { resource: ['pipeline'], operation: ['update'] } },
                    options: [
                        {
                            displayName: 'Name',
                            name: 'name',
                            type: 'string',
                            default: '',
                            routing: { send: { type: 'body', property: 'name' } },
                        },
                    ],
                },
                // Pipeline — Delete source
                {
                    displayName: 'Source',
                    name: 'source',
                    type: 'options',
                    options: [
                        { name: 'AI Agent', value: 'ai_agent' },
                        { name: 'Human', value: 'human' },
                        { name: 'System', value: 'system' },
                    ],
                    default: 'ai_agent',
                    required: true,
                    displayOptions: { show: { resource: ['pipeline'], operation: ['delete'] } },
                    routing: { send: { type: 'query', property: 'source' } },
                },
                {
                    displayName: 'Stage ID',
                    name: 'stageId',
                    type: 'string',
                    default: '',
                    required: true,
                    displayOptions: { show: { resource: ['pipeline'], operation: ['getStage', 'updateStage', 'deleteStage'] } },
                },
                // Stage — Create
                {
                    displayName: 'Name',
                    name: 'name',
                    type: 'string',
                    default: '',
                    required: true,
                    displayOptions: { show: { resource: ['pipeline'], operation: ['createStage'] } },
                    routing: { send: { type: 'body', property: 'name' } },
                },
                {
                    displayName: 'Source',
                    name: 'source',
                    type: 'options',
                    options: [
                        { name: 'AI Agent', value: 'ai_agent' },
                        { name: 'Human', value: 'human' },
                        { name: 'System', value: 'system' },
                    ],
                    default: 'ai_agent',
                    required: true,
                    displayOptions: { show: { resource: ['pipeline'], operation: ['createStage'] } },
                    routing: { send: { type: 'body', property: 'source' } },
                },
                {
                    displayName: 'Additional Fields',
                    name: 'additionalFields',
                    type: 'collection',
                    placeholder: 'Add Field',
                    default: {},
                    displayOptions: { show: { resource: ['pipeline'], operation: ['createStage'] } },
                    options: [
                        {
                            displayName: 'Color',
                            name: 'color',
                            type: 'string',
                            default: '',
                            description: 'Hex color for the stage (e.g. #3B82F6)',
                            routing: { send: { type: 'body', property: 'color' } },
                        },
                        {
                            displayName: 'Order',
                            name: 'order',
                            type: 'number',
                            default: 0,
                            description: 'Position/rank of the stage',
                            routing: { send: { type: 'body', property: 'order' } },
                        },
                        {
                            displayName: 'Target Volume',
                            name: 'target_volume',
                            type: 'number',
                            default: 0,
                            routing: { send: { type: 'body', property: 'target_volume' } },
                        },
                    ],
                },
                // Stage — Update
                {
                    displayName: 'Source',
                    name: 'source',
                    type: 'options',
                    options: [
                        { name: 'AI Agent', value: 'ai_agent' },
                        { name: 'Human', value: 'human' },
                        { name: 'System', value: 'system' },
                    ],
                    default: 'ai_agent',
                    required: true,
                    displayOptions: { show: { resource: ['pipeline'], operation: ['updateStage'] } },
                    routing: { send: { type: 'body', property: 'source' } },
                },
                {
                    displayName: 'Update Fields',
                    name: 'updateFields',
                    type: 'collection',
                    placeholder: 'Add Field',
                    default: {},
                    displayOptions: { show: { resource: ['pipeline'], operation: ['updateStage'] } },
                    options: [
                        {
                            displayName: 'Name',
                            name: 'name',
                            type: 'string',
                            default: '',
                            routing: { send: { type: 'body', property: 'name' } },
                        },
                        {
                            displayName: 'Color',
                            name: 'color',
                            type: 'string',
                            default: '',
                            routing: { send: { type: 'body', property: 'color' } },
                        },
                        {
                            displayName: 'Order',
                            name: 'order',
                            type: 'number',
                            default: 0,
                            routing: { send: { type: 'body', property: 'order' } },
                        },
                    ],
                },
                // Stage — Delete source
                {
                    displayName: 'Source',
                    name: 'source',
                    type: 'options',
                    options: [
                        { name: 'AI Agent', value: 'ai_agent' },
                        { name: 'Human', value: 'human' },
                        { name: 'System', value: 'system' },
                    ],
                    default: 'ai_agent',
                    required: true,
                    displayOptions: { show: { resource: ['pipeline'], operation: ['deleteStage'] } },
                    routing: { send: { type: 'query', property: 'source' } },
                },
                // ═══════════════════════════════════════════
                //              USER
                // ═══════════════════════════════════════════
                {
                    displayName: 'Operation',
                    name: 'operation',
                    type: 'options',
                    noDataExpression: true,
                    displayOptions: { show: { resource: ['user'] } },
                    options: [
                        { name: 'Invite', value: 'invite', description: 'Invite a user to the organization', action: 'Invite a user', routing: { request: { method: 'POST', url: '/api/users' } } },
                        { name: 'List', value: 'list', description: 'List all organization members', action: 'List users', routing: { request: { method: 'GET', url: '/api/users' } } },
                        { name: 'Remove', value: 'remove', description: 'Remove a user from the organization', action: 'Remove a user', routing: { request: { method: 'DELETE', url: '=/api/users/{{$parameter["memberId"]}}' } } },
                    ],
                    default: 'list',
                },
                // User — ID (for Remove)
                {
                    displayName: 'Member ID',
                    name: 'memberId',
                    type: 'string',
                    default: '',
                    required: true,
                    description: 'ID of the member to remove',
                    displayOptions: { show: { resource: ['user'], operation: ['remove'] } },
                },
                // User — Invite
                {
                    displayName: 'Email',
                    name: 'email',
                    type: 'string',
                    default: '',
                    required: true,
                    placeholder: 'user@example.com',
                    displayOptions: { show: { resource: ['user'], operation: ['invite'] } },
                    routing: { send: { type: 'body', property: 'email' } },
                },
                {
                    displayName: 'Role ID',
                    name: 'role_id',
                    type: 'string',
                    default: '',
                    required: true,
                    description: 'ID of the role to assign to the user',
                    displayOptions: { show: { resource: ['user'], operation: ['invite'] } },
                    routing: { send: { type: 'body', property: 'role_id' } },
                },
                {
                    displayName: 'Source',
                    name: 'source',
                    type: 'options',
                    options: [
                        { name: 'AI Agent', value: 'ai_agent' },
                        { name: 'Human', value: 'human' },
                        { name: 'System', value: 'system' },
                    ],
                    default: 'ai_agent',
                    required: true,
                    displayOptions: { show: { resource: ['user'], operation: ['invite', 'remove'] } },
                    routing: { send: { type: 'body', property: 'source' } },
                },
                {
                    displayName: 'Additional Fields',
                    name: 'additionalFields',
                    type: 'collection',
                    placeholder: 'Add Field',
                    default: {},
                    displayOptions: { show: { resource: ['user'], operation: ['invite'] } },
                    options: [
                        {
                            displayName: 'Full Name',
                            name: 'full_name',
                            type: 'string',
                            default: '',
                            description: 'Optional full name for the invited user',
                            routing: { send: { type: 'body', property: 'full_name' } },
                        },
                    ],
                },
                // ═══════════════════════════════════════════
                //          NOTIFICATION
                // ═══════════════════════════════════════════
                {
                    displayName: 'Operation',
                    name: 'operation',
                    type: 'options',
                    noDataExpression: true,
                    displayOptions: { show: { resource: ['notification'] } },
                    options: [
                        { name: 'Send', value: 'send', description: 'Send a notification', action: 'Send a notification', routing: { request: { method: 'POST', url: '/api/notifications' } } },
                    ],
                    default: 'send',
                },
                {
                    displayName: 'Event ID',
                    name: 'event_id',
                    type: 'string',
                    default: '',
                    description: 'The ID of the pre-configured notification event (e.g. evt_BB8ClTpZ1G)',
                    required: true,
                    displayOptions: { show: { resource: ['notification'], operation: ['send'] } },
                    routing: { send: { type: 'body', property: 'event_id' } },
                },
                {
                    displayName: 'Source',
                    name: 'source',
                    type: 'options',
                    options: [
                        { name: 'AI Agent', value: 'ai_agent' },
                        { name: 'Human', value: 'human' },
                    ],
                    default: 'ai_agent',
                    required: true,
                    displayOptions: { show: { resource: ['notification'], operation: ['send'] } },
                    routing: { send: { type: 'body', property: 'source' } },
                },
                {
                    displayName: 'Additional Fields',
                    name: 'additionalFields',
                    type: 'collection',
                    placeholder: 'Add Field',
                    default: {},
                    displayOptions: { show: { resource: ['notification'], operation: ['send'] } },
                    options: [
                        {
                            displayName: 'Recipient Member ID',
                            name: 'recipient_member_id',
                            type: 'string',
                            default: '',
                            description: 'Send to a specific member. Leave empty to broadcast to all.',
                            routing: { send: { type: 'body', property: 'recipient_member_id' } },
                        },
                        {
                            displayName: 'Link URL',
                            name: 'link_url',
                            type: 'string',
                            default: '',
                            description: 'URL to link to when notification is clicked',
                            routing: { send: { type: 'body', property: 'link_url' } },
                        },
                    ],
                },
            ],
        };
        this.methods = {
            loadOptions: {
                async getPipelines() {
                    const credentials = await this.getCredentials('atlasEyeApi');
                    const baseUrl = credentials.baseUrl.replace(/\/$/, '');
                    const response = await this.helpers.httpRequestWithAuthentication.call(this, 'atlasEyeApi', {
                        method: 'GET',
                        url: `${baseUrl}/api/pipelines`,
                        json: true,
                    });
                    const returnData = [];
                    for (const pipeline of response || []) {
                        returnData.push({
                            name: pipeline.name,
                            value: pipeline.id,
                        });
                    }
                    return returnData;
                },
                async getStages() {
                    // Read pipeline_id - try root-level first, then nested filters
                    let pipelineId;
                    try {
                        pipelineId = this.getCurrentNodeParameter('pipeline_id');
                    }
                    catch (e) {
                        // Not at root level, check filters
                    }
                    if (!pipelineId) {
                        try {
                            const filters = this.getCurrentNodeParameter('filters');
                            if (filters && filters.pipeline_id) {
                                pipelineId = filters.pipeline_id;
                            }
                        }
                        catch (e) {
                            // No filters
                        }
                    }
                    if (!pipelineId)
                        return [];
                    const credentials = await this.getCredentials('atlasEyeApi');
                    const baseUrl = credentials.baseUrl.replace(/\/$/, '');
                    // Call the dedicated stages endpoint
                    const response = await this.helpers.httpRequestWithAuthentication.call(this, 'atlasEyeApi', {
                        method: 'GET',
                        url: `${baseUrl}/api/pipelines/${pipelineId}/stages`,
                        json: true,
                    });
                    const returnData = [];
                    for (const stage of response || []) {
                        returnData.push({
                            name: stage.name,
                            value: stage.id,
                        });
                    }
                    return returnData;
                },
                async getAllCustomFields() {
                    const credentials = await this.getCredentials('atlasEyeApi');
                    const baseUrl = credentials.baseUrl.replace(/\/$/, '');
                    const response = await this.helpers.httpRequestWithAuthentication.call(this, 'atlasEyeApi', {
                        method: 'GET',
                        url: `${baseUrl}/api/custom-fields`,
                        json: true,
                    });
                    const returnData = [];
                    for (const field of response || []) {
                        let label = `${field.name} (${field.category})`;
                        // Add type hint
                        if (field.type === 'select' && Array.isArray(field.options) && field.options.length > 0) {
                            label += ` [select: ${field.options.join(', ')}]`;
                        }
                        else if (field.type === 'multi_select' && Array.isArray(field.options) && field.options.length > 0) {
                            label += ` [multi_select: ${field.options.join(', ')}]`;
                        }
                        else if (field.type === 'datetime') {
                            label += ' [datetime — use ISO 8601]';
                        }
                        else if (field.type === 'date') {
                            label += ' [date — use ISO 8601]';
                        }
                        else {
                            label += ` [${field.type}]`;
                        }
                        returnData.push({
                            name: label,
                            value: field.id,
                        });
                    }
                    return returnData;
                },
                async getAllCustomFieldValues() {
                    const credentials = await this.getCredentials('atlasEyeApi');
                    const baseUrl = credentials.baseUrl.replace(/\/$/, '');
                    const response = await this.helpers.httpRequestWithAuthentication.call(this, 'atlasEyeApi', {
                        method: 'GET',
                        url: `${baseUrl}/api/custom-fields`,
                        json: true,
                    });
                    // Try to get the currently selected field to filter options
                    let selectedFieldId = '';
                    try {
                        selectedFieldId = this.getCurrentNodeParameter('fieldId') || '';
                    }
                    catch (e) {
                        // Fallback: show all options if getCurrentNodeParameter fails
                    }
                    const returnData = [];
                    for (const field of response || []) {
                        if ((field.type === 'select' || field.type === 'multi_select') && Array.isArray(field.options)) {
                            // If we know which field is selected, only show that field's options
                            if (selectedFieldId && field.id !== selectedFieldId)
                                continue;
                            for (const opt of field.options) {
                                returnData.push({
                                    name: selectedFieldId ? opt : `${opt} — ${field.name}`,
                                    value: opt,
                                });
                            }
                        }
                    }
                    return returnData;
                },
                async getTags() {
                    const credentials = await this.getCredentials('atlasEyeApi');
                    const baseUrl = credentials.baseUrl.replace(/\/$/, '');
                    const response = await this.helpers.httpRequestWithAuthentication.call(this, 'atlasEyeApi', {
                        method: 'GET',
                        url: `${baseUrl}/api/tags`,
                        json: true,
                    });
                    const returnData = [];
                    for (const tag of response || []) {
                        returnData.push({
                            name: tag.name,
                            value: tag.id,
                        });
                    }
                    return returnData;
                },
                async getMembers() {
                    var _a, _b;
                    const credentials = await this.getCredentials('atlasEyeApi');
                    const baseUrl = credentials.baseUrl.replace(/\/$/, '');
                    const response = await this.helpers.httpRequestWithAuthentication.call(this, 'atlasEyeApi', {
                        method: 'GET',
                        url: `${baseUrl}/api/users`,
                        json: true,
                    });
                    const returnData = [];
                    for (const member of response || []) {
                        const name = ((_a = member.profiles) === null || _a === void 0 ? void 0 : _a.full_name) || ((_b = member.profiles) === null || _b === void 0 ? void 0 : _b.email) || member.id;
                        returnData.push({
                            name,
                            value: member.id, // we map to member.id which leads owner_member_id expects
                        });
                    }
                    return returnData;
                },
            },
        };
    }
}
exports.AtlasEye = AtlasEye;
//# sourceMappingURL=AtlasEye.node.js.map