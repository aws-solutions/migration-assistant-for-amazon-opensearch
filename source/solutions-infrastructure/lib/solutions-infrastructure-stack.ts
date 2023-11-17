// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0

import {Aws, CfnMapping, CfnParameter, Fn, Stack, StackProps, Tags} from 'aws-cdk-lib';
import {Construct} from 'constructs';
import {
  BlockDeviceVolume,
  CloudFormationInit,
  InitCommand,
  InitElement,
  InitFile,
  Instance,
  InstanceClass,
  InstanceSize,
  InstanceType,
  IpAddresses,
  MachineImage,
  SubnetType,
  Vpc
} from "aws-cdk-lib/aws-ec2";
import {InstanceProfile, ManagedPolicy, Role, ServicePrincipal} from "aws-cdk-lib/aws-iam";
import {CfnDocument} from "aws-cdk-lib/aws-ssm";
import {Application, AttributeGroup} from "@aws-cdk/aws-servicecatalogappregistry-alpha";

export interface SolutionsInfrastructureStackProps extends StackProps {
  readonly solutionId: string;
  readonly solutionName: string;
  readonly solutionVersion: string;
  readonly codeBucket: string;
}

export function applyAppRegistry(stack: Stack, stage: string, infraProps: SolutionsInfrastructureStackProps): string {
  const application = new Application(stack, "AppRegistry", {
    applicationName: Fn.join("-", [
      infraProps.solutionName,
      Aws.REGION,
      Aws.ACCOUNT_ID,
      stage // If your solution supports multiple deployments in the same region, add stage to the application name to make it unique.
    ]),
    description: `Service Catalog application to track and manage all your resources for the solution ${infraProps.solutionName}`,
  });
  application.associateApplicationWithStack(stack);
  Tags.of(application).add("Solutions:SolutionID", infraProps.solutionId);
  Tags.of(application).add("Solutions:SolutionName", infraProps.solutionName);
  Tags.of(application).add("Solutions:SolutionVersion", infraProps.solutionVersion);
  Tags.of(application).add("Solutions:ApplicationType", "AWS-Solutions");

  const attributeGroup = new AttributeGroup(
      stack,
      "DefaultApplicationAttributes",
      {
        attributeGroupName: Fn.join("-", [
          Aws.REGION,
          stage,
          "attributes"
        ]),
        description: "Attribute group for solution information",
        attributes: {
          applicationType: "AWS-Solutions",
          version: infraProps.solutionVersion,
          solutionID: infraProps.solutionId,
          solutionName: infraProps.solutionName,
        },
      }
  );
  attributeGroup.associateWith(application)
  return application.applicationArn
}

export class SolutionsInfrastructureStack extends Stack {

  constructor (scope: Construct, id: string, props: SolutionsInfrastructureStackProps) {
    super(scope, id, props);

    // CFN template format version
    this.templateOptions.templateFormatVersion = '2010-09-09';

    // CFN Mappings
    new CfnMapping(this, 'Solution', {
      mapping: {
        Config: {
          CodeVersion: props.solutionVersion,
          KeyPrefix: `${props.solutionName}/${props.solutionVersion}`,
          S3Bucket: props.codeBucket,
          SendAnonymousUsage: 'No',
          SolutionId: props.solutionId
        }
      }
    });

    const stageParameter = new CfnParameter(this, 'Stage', {
      type: 'String',
      description: 'Specify the stage identifier which will be used in naming resources, e.g. dev,gamma,wave1',
      default: 'dev',
      noEcho: false
    });

    const appRegistryAppARN = applyAppRegistry(this, stageParameter.valueAsString, props)

    // Ideally we would have an option to import an existing VPC but unfortunately without being in control of the
    // imported vpc we can not get the needed values at synthesis time and VPC lookup() does not allow token values.
    // More details can be found here: https://github.com/aws/aws-cdk/issues/3600
    const vpc = new Vpc(this, 'BootstrapVPC', {
      // IP space should be customized for use cases that have specific IP range needs
      ipAddresses: IpAddresses.cidr('10.0.0.0/16'),
      maxAzs:  1,
      subnetConfiguration: [
        // Outbound internet access for private subnets require a NAT Gateway which must live in
        // a public subnet
        {
          name: 'public-subnet',
          subnetType: SubnetType.PUBLIC,
          cidrMask: 24,
        },
        {
          name: 'private-subnet',
          subnetType: SubnetType.PRIVATE_WITH_EGRESS,
          cidrMask: 24,
        },
      ],
    });

    new CfnDocument(this, "BootstrapShellDoc", {
      name: `SSM-${stageParameter.valueAsString}-BootstrapShell`,
      documentType: "Session",
      content: {
        "schemaVersion": "1.0",
        "description": "Document to hold regional settings for Session Manager",
        "sessionType": "Standard_Stream",
        "inputs": {
          "cloudWatchLogGroupName": "",
          "cloudWatchEncryptionEnabled": true,
          "cloudWatchStreamingEnabled": false,
          "kmsKeyId": "",
          "runAsEnabled": false,
          "runAsDefaultUser": "",
          "idleSessionTimeout": "60",
          "maxSessionDuration": "",
          "shellProfile": {
            "linux": "cd /opensearch-migrations && sudo -s"
          }
        }
      }
    })

    const bootstrapFile = InitFile.fromFileInline("/opensearch-migrations/initBootstrap.sh", './initBootstrap.sh', {
          mode: "000744"
    })
    const solutionsUserAgent = `AwsSolution/${props.solutionId}/${props.solutionVersion}`
    const cfnInitConfig : InitElement[] = [
      InitCommand.shellCommand(`echo "export MIGRATIONS_APP_REGISTRY_ARN=${appRegistryAppARN}; export CUSTOM_REPLAYER_USER_AGENT=${solutionsUserAgent}" > /etc/profile.d/solutionsEnv.sh`),
      bootstrapFile
    ]

    const bootstrapRole = new Role(this, 'BootstrapRole', {
      assumedBy: new ServicePrincipal('ec2.amazonaws.com'),
      description: 'EC2 Bootstrap Role'
    });
    bootstrapRole.addManagedPolicy(ManagedPolicy.fromAwsManagedPolicyName('AdministratorAccess'))

    new InstanceProfile(this, 'BootstrapInstanceProfile', {
      instanceProfileName: `bootstrap-${stageParameter.valueAsString}-instance-profile`,
      role: bootstrapRole
    })

    new Instance(this, 'BootstrapEC2Instance', {
      vpc: vpc,
      instanceName: `bootstrap-${stageParameter.valueAsString}-instance`,
      instanceType: InstanceType.of(InstanceClass.T2, InstanceSize.LARGE),
      machineImage: MachineImage.latestAmazonLinux2023(),
      role: bootstrapRole,
      blockDevices: [
        {
          deviceName: "/dev/xvda",
          volume: BlockDeviceVolume.ebs(50)
        }
      ],
      init: CloudFormationInit.fromElements(...cfnInitConfig)
    });

  }
}
