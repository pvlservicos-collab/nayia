"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.AtlasEyeApi = void 0;
class AtlasEyeApi {
    constructor() {
        this.name = 'atlasEyeApi';
        this.displayName = 'Atlas Eye API';
        this.documentationUrl = 'https://atlaseye.com/docs/api';
        this.properties = [
            {
                displayName: 'API Token',
                name: 'apiToken',
                type: 'string',
                typeOptions: { password: true },
                default: '',
                required: true,
                description: 'Your Atlas Eye API token (starts with atl_). Generate it in Settings → API.',
            },
            {
                displayName: 'Base URL',
                name: 'baseUrl',
                type: 'string',
                default: 'https://api.atlaseye.com',
                required: true,
                description: 'The base URL of your Atlas Eye instance (without trailing slash).',
            },
        ];
        this.authenticate = {
            type: 'generic',
            properties: {
                headers: {
                    Authorization: '=Bearer {{$credentials.apiToken}}',
                },
            },
        };
        this.test = {
            request: {
                baseURL: '={{$credentials.baseUrl}}',
                url: '/api/pipelines',
                method: 'GET',
            },
        };
    }
}
exports.AtlasEyeApi = AtlasEyeApi;
//# sourceMappingURL=AtlasEyeApi.credentials.js.map