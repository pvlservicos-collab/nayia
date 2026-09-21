import { INodeType, INodeTypeDescription, ILoadOptionsFunctions, INodePropertyOptions } from 'n8n-workflow';
export declare class AtlasEye implements INodeType {
    description: INodeTypeDescription;
    methods: {
        loadOptions: {
            getPipelines(this: ILoadOptionsFunctions): Promise<INodePropertyOptions[]>;
            getStages(this: ILoadOptionsFunctions): Promise<INodePropertyOptions[]>;
            getAllCustomFields(this: ILoadOptionsFunctions): Promise<INodePropertyOptions[]>;
            getAllCustomFieldValues(this: ILoadOptionsFunctions): Promise<INodePropertyOptions[]>;
            getTags(this: ILoadOptionsFunctions): Promise<INodePropertyOptions[]>;
            getMembers(this: ILoadOptionsFunctions): Promise<INodePropertyOptions[]>;
        };
    };
}
//# sourceMappingURL=AtlasEye.node.d.ts.map