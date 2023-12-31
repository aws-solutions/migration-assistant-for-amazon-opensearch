// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0

import '@aws-cdk/assert/jest';
import { Template } from 'aws-cdk-lib/assertions';
import { App } from 'aws-cdk-lib';
import { SolutionsInfrastructureStack } from '../lib/solutions-infrastructure-stack';

test('EC2 bootstrap instance is created', () => {
  const app = new App();
  const stack = new SolutionsInfrastructureStack(app, 'TestBootstrapStack', {
    solutionId: 'SO0000',
    solutionName: 'test-solution',
    solutionVersion: '0.0.1',
    codeBucket: 'test-bucket'
  });
  const template = Template.fromStack(stack);
  template.hasResourceProperties('AWS::EC2::Instance', {
    InstanceType: "t2.large"
  });
});
