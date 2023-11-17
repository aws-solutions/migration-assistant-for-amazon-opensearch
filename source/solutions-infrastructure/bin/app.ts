#!/usr/bin/env node
// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0

import 'source-map-support/register';
import { App, DefaultStackSynthesizer } from 'aws-cdk-lib';
import { SolutionsInfrastructureStack, SolutionsInfrastructureStackProps } from '../lib/solutions-infrastructure-stack';

const getProps = (): SolutionsInfrastructureStackProps => {
  const { CODE_BUCKET, SOLUTION_NAME, CODE_VERSION } = process.env;
  if (typeof CODE_BUCKET !== 'string' || CODE_BUCKET.trim() === '') {
    throw new Error('Missing required environment variable: CODE_BUCKET');
  }

  if (typeof SOLUTION_NAME !== 'string' || SOLUTION_NAME.trim() === '') {
    throw new Error('Missing required environment variable: SOLUTION_NAME');
  }

  if (typeof CODE_VERSION !== 'string' || CODE_VERSION.trim() === '') {
    throw new Error('Missing required environment variable: CODE_VERSION');
  }

  const codeBucket = CODE_BUCKET;
  const solutionVersion = CODE_VERSION;
  const solutionId = 'SO0290';
  const solutionName = SOLUTION_NAME;
  const description = `(${solutionId}) - The AWS CloudFormation template for deployment of the ${solutionName}. Version ${solutionVersion}`;

  // Uncomment for local testing
  // const codeBucket = 'unknown';
  // const solutionVersion = "1.0.0";
  // const solutionId = 'SO0290';
  // const solutionName = 'migration-assistant-for-amazon-opensearch';
  // const description = `(${solutionId}) - The AWS CloudFormation template for deployment of the ${solutionName}. Version ${solutionVersion}`;

  return {
    codeBucket,
    solutionVersion,
    solutionId,
    solutionName,
    description
  };
};

const app = new App();
const infraProps = getProps()
new SolutionsInfrastructureStack(app, 'OSMigrations-Bootstrap', {
  synthesizer: new DefaultStackSynthesizer({
    generateBootstrapVersionRule: false
  }),
  ...infraProps
});